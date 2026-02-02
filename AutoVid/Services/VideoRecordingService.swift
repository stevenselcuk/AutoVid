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
    
    // Pending configuration for lazy initialization
    private var pendingURL: URL?
    private var pendingBitrate: Int = 24_000_000

    func start(url: URL, width: Int? = nil, height: Int? = nil, bitrate: Int = 24_000_000) async throws {
        if isRecording {
            _ = try? await stop()
        }
        
        // We now ignore the passed width/height for the actual writer configuration,
        // relying on the first frame to determine truth.
        self.pendingURL = url
        self.pendingBitrate = bitrate
        self.isRecording = true
        self.firstSampleTime = .invalid
        self.assetWriter = nil
        self.videoInput = nil
        
        print("🎥 [VideoRecordingService] Started (Pending). Waiting for first frame to determine resolution...")
    }

    func stop() async throws -> URL {
        guard let writer = assetWriter, writer.status == .writing else {
            // If we never started writing (no frames), just return the pending URL or error
            if isRecording, let url = pendingURL {
                 isRecording = false
                 // Create an empty file or just return. Returning the URL might be misleading if empty.
                 // But for now, let's just return it.
                 return url
            }
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
        guard isRecording else { return }
        
        // Lazy Initialization
        if assetWriter == nil {
            guard let url = pendingURL else { return }
            do {
                try setupWriter(url: url, sampleBuffer: sampleBuffer)
            } catch {
                print("❌ [VideoRecordingService] Failed to setup writer: \(error)")
                isRecording = false
                return
            }
        }
        
        guard let input = videoInput, input.isReadyForMoreMediaData else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if firstSampleTime == .invalid {
            firstSampleTime = pts
            assetWriter?.startSession(atSourceTime: pts)
        }
        
        input.append(sampleBuffer)
    }
    
    private func setupWriter(url: URL, sampleBuffer: CMSampleBuffer) throws {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw NSError(domain: "VideoRecordingService", code: 5, userInfo: [NSLocalizedDescriptionKey: "No format description"])
        }
        
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)
        
        self.detectedWidth = width
        self.detectedHeight = height
        
        print("🔍 [VideoRecordingService] First frame detected: \(width)x\(height). Initializing writer...")
        
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        self.assetWriter = writer
        
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: pendingBitrate,
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
            print("✅ [VideoRecordingService] Writer initialized successfully at \(width)x\(height)")
        } else {
            throw writer.error ?? NSError(domain: "VideoRecordingService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to start writing"])
        }
    }
}

