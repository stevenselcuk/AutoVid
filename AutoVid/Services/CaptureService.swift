import AVFoundation
import AVFoundation
import CoreMedia
import CoreMediaIO

protocol CaptureServiceProtocol: AnyObject, Sendable {
    var detectedDimensions: (width: Int, height: Int) { get }
    
    func configureSession(device: AVCaptureDevice) throws
    func startSession()
    func stopSession()
    
    func startRecording(
        url: URL,
        width: Int,
        height: Int,
        bitrate: Int,
        recorder: VideoRecordingServiceProtocol,
        completion: @escaping (Bool) -> Void
    )
    
    func stopRecording(completion: @escaping (URL?) -> Void)
}

final class CaptureService: NSObject, CaptureServiceProtocol, @unchecked Sendable {
    
    
    private let sessionQueue = DispatchQueue(label: "com.autovid.session", qos: .userInitiated)
    private let outputQueue = DispatchQueue(label: "com.autovid.output", qos: .userInteractive)
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private(set) var detectedDimensions: (width: Int, height: Int) = (AppConfig.Configuration.Capture.targetWidth, AppConfig.Configuration.Capture.targetHeight)
    
    nonisolated(unsafe) private var isRecording = false
    nonisolated(unsafe) private var activeRecorder: VideoRecordingServiceProtocol?
    
    override init() {
        super.init()
        self.initializeDAL()
    }
    
    private func initializeDAL() {
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let size = MemoryLayout<UInt32>.size
        _ = CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil, UInt32(size), &allow)
    }
    
    
    func configureSession(device: AVCaptureDevice) throws {
        
        try sessionQueue.sync {
            let session = AVCaptureSession()
            session.beginConfiguration()
            
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                throw NSError(domain: "CaptureService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
            }
            
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            output.setSampleBufferDelegate(self, queue: outputQueue)
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            } else {
                throw NSError(domain: "CaptureService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add video output"])
            }
            
            session.commitConfiguration()
            self.captureSession = session
            self.videoOutput = output
            
            let formatDescription = device.activeFormat.formatDescription
            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
            
            let w = Int(dimensions.width)
            let h = Int(dimensions.height)
            
            print("🔍 [CaptureService] Device active format: \(w)x\(h)")
            
            if w > 0 && h > 0 {
                // If we have valid dimensions, strictly use them.
                // We do NOT want to inject defaults if the device says something else.
                self.detectedDimensions = (w, h)
            } else {
                print("⚠️ [CaptureService] Detected 0x0 resolution, falling back to defaults")
                self.detectedDimensions = (AppConfig.Configuration.Capture.targetWidth, AppConfig.Configuration.Capture.targetHeight)
            }
            
            print("📸 [CaptureService] Configured with resolution: \(self.detectedDimensions)")
        }
    }
    
    func startSession() {
        sessionQueue.async {
            guard let session = self.captureSession, !session.isRunning else { return }
            session.startRunning()
            print("📸 [CaptureService] Session started")
        }
    }
    
    func stopSession() {
        sessionQueue.async {
            guard let session = self.captureSession, session.isRunning else { return }
            session.stopRunning()
            print("📸 [CaptureService] Session stopped")
        }
    }
    
    func startRecording(
        url: URL,
        width: Int,
        height: Int,
        bitrate: Int,
        recorder: VideoRecordingServiceProtocol,
        completion: @escaping (Bool) -> Void
    ) {
        sessionQueue.async {
            self.activeRecorder = recorder
            
            Task {
                do {
                    // We pass 0 for width/height because the recorder now uses Lazy Initialization
                    // to detect the exact resolution from the first frame.
                    try await recorder.start(url: url, width: 0, height: 0, bitrate: bitrate)
                    self.isRecording = true
                    print("🎥 [CaptureService] Recording started (Lazy Init mode)")
                    completion(true)
                } catch {
                    self.isRecording = false
                    print("❌ [CaptureService] Recording failed to start: \(error)")
                    completion(false)
                }
            }
        }
    }
    
    func stopRecording(completion: @escaping (URL?) -> Void) {
        sessionQueue.async {
            guard self.isRecording, let recorder = self.activeRecorder else {
                completion(nil)
                return
            }
            
            self.isRecording = false
            
            Task {
                do {
                    let url = try await recorder.stop()
                    print("🎥 [CaptureService] Recording stopped, URL: \(url)")
                    completion(url)
                } catch {
                    print("❌ [CaptureService] Stop failed: \(error)")
                    completion(nil)
                }
            }
        }
    }
    
    deinit {
        captureSession?.stopRunning()
    }
}


extension CaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRecording, let recorder = activeRecorder else { return }
        
        Task { await recorder.append(sampleBuffer) }
    }
}

