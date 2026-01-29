@preconcurrency import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DashboardViewModel: NSObject, ObservableObject {
    private let xcodeProjectService: XcodeProjectServiceProtocol
    private let automationService: AutomationServiceProtocol
    private let deviceDiscoveryService: DeviceDiscoveryServiceProtocol
    private let captureService: CaptureServiceProtocol
    
    let videoRecorder: VideoRecordingServiceProtocol
    
    @Published var isRecording = false
    @Published var status = "IDLE"
    @Published var lastSavedURL: URL?
    
    @Published var detectedDevices: [AVCaptureDevice] = []
    @Published var availableDevices: [Device] = []
    
    @Published var availableProjects: [String] = []
    @Published var availableSchemes: [String] = []
    @Published var isLoadingProjects = false
    @Published var isLoadingSchemes = false
    
    @Published var isLoadingDevices = false
    @Published var isBuildingTests = false
    @Published var buildOutput: String = ""
    
    @AppStorage("projectPath") var projectPath = ""
    @AppStorage("schemeName") var schemeName = ""
    @AppStorage("deviceName") var deviceName = ""
    
    var onRecordingFinished: ((URL) -> Void)?
    
    @Published var recordedVideoURL: URL?
    
    private var cancellables = Set<AnyCancellable>()
    
    private static let fileDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmmss"
        return df
    }()
    
    convenience override init() {
        let container = DependencyContainer.shared
        self.init(
            xcodeProjectService: container.xcodeProjectService,
            automationService: container.automationService,
            deviceDiscoveryService: container.deviceDiscoveryService,
            recordingService: container.recordingService,
            captureService: container.captureService
        )
    }
    
    init(
        xcodeProjectService: XcodeProjectServiceProtocol,
        automationService: AutomationServiceProtocol,
        deviceDiscoveryService: DeviceDiscoveryServiceProtocol,
        recordingService: VideoRecordingServiceProtocol,
        captureService: CaptureServiceProtocol
    ) {
        self.xcodeProjectService = xcodeProjectService
        self.automationService = automationService
        self.deviceDiscoveryService = deviceDiscoveryService
        self.videoRecorder = recordingService
        self.captureService = captureService
        
        super.init()
        
        setupBindings()
        
    }
    
    private func setupBindings() {
        xcodeProjectService.availableProjectsPublisher
            .assign(to: &$availableProjects)
        
        xcodeProjectService.availableSchemesPublisher
            .assign(to: &$availableSchemes)
            
        xcodeProjectService.isLoadingProjectsPublisher
            .assign(to: &$isLoadingProjects)
            
        xcodeProjectService.isLoadingSchemesPublisher
            .assign(to: &$isLoadingSchemes)
        
        deviceDiscoveryService.detectedDevicesPublisher
            .assign(to: &$detectedDevices)
            
        deviceDiscoveryService.availableDevicesPublisher
            .sink { [weak self] devices in
                guard let self = self else { return }
                self.availableDevices = devices
                
                if self.deviceName.isEmpty && !devices.isEmpty {
                    if let real = devices.first(where: { $0.type == "Real" }) {
                        self.deviceName = real.name
                    } else {
                        self.deviceName = devices.first?.name ?? ""
                    }
                }
            }
            .store(in: &cancellables)
            
        deviceDiscoveryService.isLoadingDevicesPublisher
            .assign(to: &$isLoadingDevices)
        
        automationService.isBuildingTestsPublisher
            .assign(to: &$isBuildingTests)
            
        automationService.buildOutputPublisher
            .assign(to: &$buildOutput)
        
        automationService.onTestsStarted = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                print("\n🎬 [AutoVid] Tests started (callback), beginning recording...\n")
                await self.start()
            }
        }
        
        automationService.onRecordingStopRequested = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isRecording {
                    await self.stop()
                }
                
                if self.status == "Recording" {
                    self.status = "Auto Finised"
                }
            }
        }
        
        xcodeProjectService.statusPublisher
            .filter { $0 != "IDLE" && $0 != "Ready" }
            .assign(to: &$status)
            
        automationService.statusPublisher
            .filter { $0 != "IDLE" }
            .assign(to: &$status)
    }
    
    deinit {
    }
    
    
    func findXcodeProjects() {
        xcodeProjectService.findXcodeProjects()
    }
    
    func fetchSchemes(for path: String) {
        xcodeProjectService.fetchSchemes(for: path, currentScheme: schemeName)
    }
    
    
    func start() async {
        guard let device = detectedDevices.first else {
            status = "No device found"
            return
        }
        status = "Warming..."
        do {
            let url = try prepareOutputURL()
            
            try captureService.configureSession(device: device)
            let (width, height) = captureService.detectedDimensions
            
            captureService.startSession()
            
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                captureService.startRecording(
                    url: url,
                    width: width,
                    height: height,
                    bitrate: AppConfig.Configuration.Capture.bitrate,
                    recorder: self.videoRecorder
                ) { [weak self] success in
                    Task { @MainActor in
                        guard let self = self else {
                            continuation.resume()
                            return
                        }
                        
                        if success {
                            self.isRecording = true
                            self.status = "Recording"
                        } else {
                            self.isRecording = false
                            self.status = "Recorder Failed"
                            self.captureService.stopSession()
                        }
                        continuation.resume()
                    }
                }
            }
        } catch {
            status = "Error: \(error.localizedDescription)"
            isRecording = false
        }
    }
    
    func startWithAutomation() async {
        await automationService.startWithAutomation(
            projectPath: projectPath,
            schemeName: schemeName,
            deviceName: deviceName,
            availableDevices: availableDevices
        )
    }
    
    func stop() async {
        guard isRecording else { return }
        
        status = "Saving..."
        
        await withCheckedContinuation { continuation in
            captureService.stopRecording { [weak self] url in
                Task { @MainActor in
                    continuation.resume()
                    if let url = url {
                        self?.lastSavedURL = url
                        self?.recordedVideoURL = url
                        self?.status = "Success"
                        self?.isRecording = false
                        
                        self?.captureService.stopSession()
                        
                        self?.onRecordingFinished?(url)
                        
                    } else {
                        self?.status = "Error: Failed to save video"
                        self?.isRecording = false
                        self?.captureService.stopSession()
                    }
                    
                     self?.automationService.stop()
                }
            }
        }
    }
    
    private func prepareOutputURL() throws -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        let folder = movies.appendingPathComponent(AppConfig.Configuration.Capture.folderName)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent("AutoVid_\(Self.fileDateFormatter.string(from: Date())).mp4")
    }
}

