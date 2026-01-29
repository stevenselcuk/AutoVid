import AVFoundation
import Combine
import SwiftUI


@MainActor
final class EditorViewModel: NSObject, ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var trimStart: Double = 0
    @Published var trimEnd: Double = 0
    @Published var videoAspectRatio: CGFloat = 16 / 9

    @Published var selectedResolution: ExportSettings.Resolution = .appStorePreview
    @Published var customWidth: String = "1920"
    @Published var customHeight: String = "1080"
    @Published var selectedFrameRate: Int = AppConfig.Configuration.Defaults.defaultFrameRate
    @Published var selectedBitrate: Int = AppConfig.Configuration.Defaults.defaultBitrate

    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var exportError: String?
    @Published var lastExportedURL: URL?

    private var timeObserver: Any?

    let videoURL: URL
    private let asset: AVAsset

    var trimDuration: Double {
        trimEnd - trimStart
    }

    var exceedsAppStoreLimit: Bool {
        trimDuration > AppConfig.Configuration.Defaults.appStoreLimitSeconds
    }

    var durationText: String {
        let duration = trimDuration
        if exceedsAppStoreLimit {
            return String(format: "%.1fs (⚠️ App Store limit: %.0fs)", duration, AppConfig.Configuration.Defaults.appStoreLimitSeconds)
        } else {
            return String(format: "%.1fs / %.1fs", duration, AppConfig.Configuration.Defaults.appStoreLimitSeconds)
        }
    }

    init(videoURL: URL) {
        self.videoURL = videoURL
        asset = AVURLAsset(url: videoURL)
        super.init()
        setupPlayer()
    }

    nonisolated deinit {
    }

    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
    }

    private func setupPlayer() {
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        self.player = player

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let duration = try await self.asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)

                let tracks = try await self.asset.load(.tracks)
                if let videoTrack = tracks.first(where: { $0.mediaType == .video }) {
                    let naturalSize = try await videoTrack.load(.naturalSize)
                    let transform = try await videoTrack.load(.preferredTransform)

                    let size = naturalSize.applying(transform)
                    let width = abs(size.width)
                    let height = abs(size.height)

                    await MainActor.run {
                        self.duration = seconds
                        self.trimEnd = seconds
                        self.videoAspectRatio = height > 0 ? width / height : 16 / 9
                    }
                } else {
                    await MainActor.run {
                        self.duration = seconds
                        self.trimEnd = seconds
                    }
                }
            } catch {
                print("❌ Failed to load video properties: \(error)")
            }
        }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let seconds = CMTimeGetSeconds(time)
                self.currentTime = seconds

                if seconds >= self.trimEnd {
                    self.pause()
                    self.seek(to: self.trimStart)
                }
            }
        }
    }

    func play() {
        if currentTime >= trimEnd {
            seek(to: trimStart)
        }
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    func seekToStart() {
        seek(to: trimStart)
    }

    func seekToEnd() {
        seek(to: trimEnd)
    }

    func stepForward() {
        let frameTime = 1.0 / Double(selectedFrameRate)
        let newTime = min(currentTime + frameTime, trimEnd)
        seek(to: newTime)
    }

    func stepBackward() {
        let frameTime = 1.0 / Double(selectedFrameRate)
        let newTime = max(currentTime - frameTime, trimStart)
        seek(to: newTime)
    }

    func jumpForward() {
        let newTime = min(currentTime + 1.0, trimEnd)
        seek(to: newTime)
    }

    func jumpBackward() {
        let newTime = max(currentTime - 1.0, trimStart)
        seek(to: newTime)
    }

    func setTrimStartAtPlayhead() {
        updateTrimStart(currentTime)
    }

    func setTrimEndAtPlayhead() {
        updateTrimEnd(currentTime)
    }

    func updateTrimStart(_ value: Double) {
        trimStart = max(0, min(value, trimEnd - 0.5))
        if currentTime < trimStart {
            seek(to: trimStart)
        }
    }

    func updateTrimEnd(_ value: Double) {
        trimEnd = max(trimStart + 0.5, min(value, duration))
        if currentTime > trimEnd {
            seek(to: trimEnd)
        }
    }

    func exportVideo(completion: @escaping (Result<URL, Error>) -> Void) {
        guard !isExporting else { return }

        isExporting = true
        exportProgress = 0
        exportError = nil
        pause()

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let tracks = try await self.asset.load(.tracks)
                guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
                    throw NSError(domain: "EditorError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
                }

                let naturalSize = try await videoTrack.load(.naturalSize)
                let preferredTransform = try await videoTrack.load(.preferredTransform)

                let composition = AVMutableComposition()
                let startTime = CMTime(seconds: self.trimStart, preferredTimescale: 600)
                let endTime = CMTime(seconds: self.trimEnd, preferredTimescale: 600)
                let timeRange = CMTimeRange(start: startTime, duration: CMTimeSubtract(endTime, startTime))

                guard let compositionVideoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    throw NSError(domain: "EditorError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create composition track"])
                }

                try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)

                if let audioTrack = tracks.first(where: { $0.mediaType == .audio }),
                   let compositionAudioTrack = composition.addMutableTrack(
                       withMediaType: .audio,
                       preferredTrackID: kCMPersistentTrackID_Invalid
                   ) {
                    try? compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
                }

                let videoComposition = self.createVideoComposition(
                    for: composition,
                    naturalSize: naturalSize,
                    preferredTransform: preferredTransform
                )

                let outputURL = self.generateOutputURL()

                try await self.performExport(
                    composition: composition,
                    videoComposition: videoComposition,
                    outputURL: outputURL
                )

                self.lastExportedURL = outputURL
                self.isExporting = false
                completion(.success(outputURL))

                NSWorkspace.shared.activateFileViewerSelecting([outputURL])

            } catch {
                self.isExporting = false
                self.exportError = error.localizedDescription
                completion(.failure(error))
            }
        }
    }

    private func performExport(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        outputURL: URL
    ) async throws {
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw NSError(domain: "EditorError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition

        let progressTask = Task { @MainActor in
            while !Task.isCancelled {
                self.exportProgress = Double(exportSession.progress)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        do {
            try await exportSession.export(to: outputURL, as: .mp4)
            progressTask.cancel()
        } catch {
            progressTask.cancel()
            throw error
        }
    }

    private func createVideoComposition(
        for composition: AVMutableComposition,
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform
    ) -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()

        let targetSize: CGSize
        if selectedResolution == .custom {
            targetSize = CGSize(
                width: Int(customWidth) ?? 1920,
                height: Int(customHeight) ?? 1080
            )
        } else {
            targetSize = selectedResolution.size
        }

        videoComposition.renderSize = targetSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(selectedFrameRate))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: composition.tracks(withMediaType: .video).first!)

        let transform = calculateTransform(from: naturalSize, to: targetSize, sourceTransform: preferredTransform)
        layerInstruction.setTransform(transform, at: .zero)

        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        return videoComposition
    }

    private func calculateTransform(from sourceSize: CGSize, to targetSize: CGSize, sourceTransform: CGAffineTransform) -> CGAffineTransform {
        let transformedSize = sourceSize.applying(sourceTransform)
        let actualWidth = abs(transformedSize.width)
        let actualHeight = abs(transformedSize.height)

        let scaleX = targetSize.width / actualWidth
        let scaleY = targetSize.height / actualHeight
        let scale = max(scaleX, scaleY)

        let scaledWidth = actualWidth * scale
        let scaledHeight = actualHeight * scale
        let tx = (targetSize.width - scaledWidth) / 2
        let ty = (targetSize.height - scaledHeight) / 2

        return sourceTransform
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: tx / scale, y: ty / scale)
    }

    private func generateOutputURL() -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        let folder = movies.appendingPathComponent("AutoVid")

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        let originalName = videoURL.deletingPathExtension().lastPathComponent
        let filename = "\(originalName)_EDITED_\(timestamp).mp4"
        return folder.appendingPathComponent(filename)
    }
}

