import Foundation

@MainActor
final class DependencyContainer {
    static let shared = DependencyContainer()
    
    let xcodeProjectService: XcodeProjectServiceProtocol
    let automationService: AutomationServiceProtocol
    let deviceDiscoveryService: DeviceDiscoveryServiceProtocol
    let recordingService: VideoRecordingServiceProtocol
    let captureService: CaptureServiceProtocol
    
    init(
        xcodeProjectService: XcodeProjectServiceProtocol? = nil,
        automationService: AutomationServiceProtocol? = nil,
        deviceDiscoveryService: DeviceDiscoveryServiceProtocol? = nil,
        recordingService: VideoRecordingServiceProtocol? = nil,
        captureService: CaptureServiceProtocol? = nil
    ) {
        self.xcodeProjectService = xcodeProjectService ?? XcodeProjectService()
        self.automationService = automationService ?? AutomationService()
        self.deviceDiscoveryService = deviceDiscoveryService ?? DeviceDiscoveryService()
        self.recordingService = recordingService ?? VideoRecordingService()
        self.captureService = captureService ?? CaptureService()
    }
}
