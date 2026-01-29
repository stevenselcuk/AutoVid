@preconcurrency import AVFoundation
import CoreMedia

protocol VideoRecordingServiceProtocol: Sendable {
    func start(url: URL, width: Int?, height: Int?, bitrate: Int) async throws
    func stop() async throws -> URL
    func append(_ sampleBuffer: CMSampleBuffer) async
}


actor VideoRecordingService: VideoRecordingServiceProtocol {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var isRecording = false
    private var firstSampleTime: CMTime = .invalid

    private var detectedWidth: Int = 0
    private var detectedHeight: Int = 0

    func start(url: URL, width: Int? = nil, height: Int? = nil, bitrate: Int = 24_000_000) async throws {
        if isRecording {
            _ = try? await stop()
        }
        
        let finalWidth = (width != nil && width! > 0) ? width! : 1290
        let finalHeight = (height != nil && height! > 0) ? height! : 2796

        if finalWidth <= 0 || finalHeight <= 0 {
             throw NSError(domain: "VideoRecordingService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid dimensions: \(finalWidth)x\(finalHeight)"])
        }

        self.detectedWidth = finalWidth
        self.detectedHeight = finalHeight

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        self.assetWriter = writer
        
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: finalWidth,
            AVVideoHeightKey: finalHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 30,
            ],
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        self.videoInput = input

        if writer.canAdd(input) {
            writer.add(input)
        } else {
            throw NSError(domain: "VideoRecordingService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add input to writer"])
        }

        if writer.startWriting() {
            self.isRecording = true
            self.firstSampleTime = .invalid
            print("✅ [VideoRecordingService] Started recording at \(finalWidth)x\(finalHeight)")
        } else {
            throw writer.error ?? NSError(domain: "VideoRecordingService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to start writing"])
        }
    }

    func stop() async throws -> URL {
        guard let writer = assetWriter, writer.status == .writing else {
            if let writer = assetWriter {
                return writer.outputURL
            }
            throw NSError(domain: "VideoRecordingService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Writer not active"])
        }

        isRecording = false
        videoInput?.markAsFinished()
        
        
        return await withCheckedContinuation { continuation in
            let url = writer.outputURL
            writer.finishWriting {
                print("✅ [VideoRecordingService] Finished writing to \(url.lastPathComponent)")
                continuation.resume(returning: url)
            }
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, let input = videoInput, input.isReadyForMoreMediaData else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if firstSampleTime == .invalid {
            firstSampleTime = pts
            assetWriter?.startSession(atSourceTime: pts)
        }
        
        
        input.append(sampleBuffer)
    }
}

