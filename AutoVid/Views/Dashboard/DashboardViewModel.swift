import AVFoundation
import Combine
import SwiftUI
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class DashboardViewModel {
    // MARK: - Dependencies
    private let xcodeProjectService: XcodeProjectServiceProtocol
    // We keep the protocol, but Observation works through it if the underlying instance is @Observable
    let automationService: AutomationServiceProtocol
    private let deviceDiscoveryService: DeviceDiscoveryServiceProtocol
    private let captureService: CaptureServiceProtocol
    let videoRecorder: VideoRecordingServiceProtocol
    
    // MARK: - Published State (Observation)
    var isRecording = false
    
    // We use a private backing store for status to handle priority between services
    private var _localStatus: String = "IDLE"
    
    // Computed status aggregates various sources
    var status: String {
        // If we are actively doing something local, show that
        if isRecording || _localStatus == "Warming..." || _localStatus == "Saving..." || _localStatus == "Success" || _localStatus.contains("Error") {
            return _localStatus
        }
        // Otherwise show automation status if it's busy
        if automationService.status != "IDLE" && automationService.status != "Ready" {
            return automationService.status
        }
        // Fallback to Xcode service status (we assume it pushes status to _localStatus via sink below, or we could expose it directly)
        return _localStatus
    }
    
    var lastSavedURL: URL?
    var recordedVideoURL: URL?
    
    var detectedDevices: [AVCaptureDevice] = []
    var availableDevices: [Device] = []
    
    var availableProjects: [String] = []
    var availableSchemes: [String] = []
    
    var isLoadingProjects = false
    var isLoadingSchemes = false
    var isLoadingDevices = false
    
    // Pass-through properties for AutomationService to allow View observation
    var isBuildingTests: Bool {
        automationService.isBuildingTests
    }
    
    var buildOutput: String {
        automationService.buildOutput
    }
    
    // MARK: - Settings (User Defaults)
    // @AppStorage is not directly supported in @Observable classes for view updates.
    // We use standard property observation + UserDefaults.
    var projectPath: String {
        didSet { UserDefaults.standard.set(projectPath, forKey: "projectPath") }
    }
    
    var schemeName: String {
        didSet { UserDefaults.standard.set(schemeName, forKey: "schemeName") }
    }
    
    var deviceName: String {
        didSet { UserDefaults.standard.set(deviceName, forKey: "deviceName") }
    }
    
    var onRecordingFinished: ((URL) -> Void)?
    
    private var cancellables = Set<AnyCancellable>()
    
    private static let fileDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmmss"
        return df
    }()
    
    // MARK: - Init
    
    convenience init() {
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
        
        // Load Defaults
        self.projectPath = UserDefaults.standard.string(forKey: "projectPath") ?? ""
        self.schemeName = UserDefaults.standard.string(forKey: "schemeName") ?? ""
        self.deviceName = UserDefaults.standard.string(forKey: "deviceName") ?? ""
        
        setupLegacyBindings()
        setupAutomationCallbacks()
    }
    
    // MARK: - Setup
    
    private func setupLegacyBindings() {
        // Bridge Combine publishers from legacy services to @Observable properties
        
        xcodeProjectService.availableProjectsPublisher
            .sink { [weak self] in self?.availableProjects = $0 }
            .store(in: &cancellables)
        
        xcodeProjectService.availableSchemesPublisher
            .sink { [weak self] in self?.availableSchemes = $0 }
            .store(in: &cancellables)
            
        xcodeProjectService.isLoadingProjectsPublisher
            .sink { [weak self] in self?.isLoadingProjects = $0 }
            .store(in: &cancellables)
            
        xcodeProjectService.isLoadingSchemesPublisher
            .sink { [weak self] in self?.isLoadingSchemes = $0 }
            .store(in: &cancellables)
        
        xcodeProjectService.statusPublisher
            .filter { $0 != "IDLE" && $0 != "Ready" }
            .sink { [weak self] status in self?._localStatus = status }
            .store(in: &cancellables)
        
        deviceDiscoveryService.detectedDevicesPublisher
            .sink { [weak self] in self?.detectedDevices = $0 }
            .store(in: &cancellables)
            
        deviceDiscoveryService.availableDevicesPublisher
            .sink { [weak self] devices in
                guard let self = self else { return }
                self.availableDevices = devices
                
                // Auto-select device logic
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
            .sink { [weak self] in self?.isLoadingDevices = $0 }
            .store(in: &cancellables)
    }
    
    private func setupAutomationCallbacks() {
        // Since AutomationService is now callback/observable based (no publishers),
        // we wire up the events directly.
        
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
                
                if self._localStatus == "Recording" {
                    self._localStatus = "Auto Finished"
                }
            }
        }
    }
    
    deinit {
        // Cancellables clean up automatically
    }
    
    // MARK: - Actions
    
    func findXcodeProjects() {
        xcodeProjectService.findXcodeProjects()
    }
    
    func fetchSchemes(for path: String) {
        xcodeProjectService.fetchSchemes(for: path, currentScheme: schemeName)
    }
    
    func start() async {
        guard let device = detectedDevices.first else {
            _localStatus = "No device found"
            return
        }
        _localStatus = "Warming..."
        
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
                            self._localStatus = "Recording"
                        } else {
                            self.isRecording = false
                            self._localStatus = "Recorder Failed"
                            self.captureService.stopSession()
                        }
                        continuation.resume()
                    }
                }
            }
        } catch {
            _localStatus = "Error: \(error.localizedDescription)"
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
        
        _localStatus = "Saving..."
        
        await withCheckedContinuation { continuation in
            captureService.stopRecording { [weak self] url in
                Task { @MainActor in
                    continuation.resume()
                    if let url = url {
                        self?.lastSavedURL = url
                        self?.recordedVideoURL = url
                        self?._localStatus = "Success"
                        self?.isRecording = false
                        
                        self?.captureService.stopSession()
                        self?.onRecordingFinished?(url)
                        
                    } else {
                        self?._localStatus = "Error: Failed to save video"
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
