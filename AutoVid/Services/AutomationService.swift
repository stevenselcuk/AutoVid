import Foundation
import Combine

@MainActor
protocol AutomationServiceProtocol: AnyObject {
    var isBuildingTests: Bool { get }
    var buildOutput: String { get }
    var status: String { get }
    
    var isBuildingTestsPublisher: AnyPublisher<Bool, Never> { get }
    var buildOutputPublisher: AnyPublisher<String, Never> { get }
    var statusPublisher: AnyPublisher<String, Never> { get }
    
    var onTestsStarted: (() -> Void)? { get set }
    var onRecordingStopRequested: (() -> Void)? { get set }
    
    func startWithAutomation(
        projectPath: String,
        schemeName: String,
        deviceName: String,
        availableDevices: [Device]
    ) async
    
    func stop()
}

@MainActor
final class AutomationService: ObservableObject, AutomationServiceProtocol {
    @Published var isBuildingTests = false
    @Published var buildOutput: String = ""
    @Published var status = "IDLE"
    
    var isBuildingTestsPublisher: AnyPublisher<Bool, Never> { $isBuildingTests.eraseToAnyPublisher() }
    var buildOutputPublisher: AnyPublisher<String, Never> { $buildOutput.eraseToAnyPublisher() }
    var statusPublisher: AnyPublisher<String, Never> { $status.eraseToAnyPublisher() }
    
    var onTestsStarted: (() -> Void)?
    var onRecordingStopRequested: (() -> Void)?
    
    private var automationProcess: Process?
    private var userInitiatedStop = false
    
    func startWithAutomation(
        projectPath: String,
        schemeName: String,
        deviceName: String,
        availableDevices: [Device]
    ) async {
        guard !projectPath.isEmpty && !schemeName.isEmpty else {
            status = "Error: Project and scheme required"
            return
        }

        status = "Building ..."
        isBuildingTests = true
        buildOutput = ""
        userInitiatedStop = false

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        let projectFlag = projectPath.hasSuffix(".xcworkspace") ? "-workspace" : "-project"

        let usbDevice = availableDevices.first(where: { $0.type == "Real" && $0.isUSBConnected })
        let targetDevice = usbDevice ?? availableDevices.first(where: { $0.name == deviceName })

        var arguments = [
            "test",
            projectFlag, projectPath,
            "-scheme", schemeName,
        ]

        if let device = targetDevice {
            arguments += ["-destination", "platform=iOS,id=\(device.udid)"]
        } else if !deviceName.isEmpty {
            arguments += ["-destination", "platform=iOS,name=\(deviceName)"]
        } else {
            arguments += ["-destination", "platform=iOS"]
        }

        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        let outHandle = pipe.fileHandleForReading
        var hasStartedRecording = false

        Task { [weak self] in
            guard let self = self else { return }
            
            for try await line in pipe.fileHandleForReading.bytes.lines {
                guard !Task.isCancelled else { break }
                
                await MainActor.run {
                    self.buildOutput = (self.buildOutput + line + "\n").suffix(500).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    print(line)
                    
                    if !hasStartedRecording && (
                        line.contains("Test Suite") && line.contains("started") ||
                        line.contains("Testing started") ||
                        line.contains("Test Case") && line.contains("started")
                    ) {
                        hasStartedRecording = true
                        print("\n🎬 [AutoVid] Tests started, beginning recording...\n")
                        self.onTestsStarted?()
                    }
                }
            }
        }
        
        print("")
        print("🚀 ========================================")
        print("🚀 RUNNING XCODEBUILD TEST")
        print("🚀 Command: xcodebuild \(arguments.joined(separator: " "))")
        print("🚀 Project: \(projectPath)")
        print("🚀 Scheme: \(schemeName)")
        print("🚀 Device: \(targetDevice?.name ?? deviceName) (\(targetDevice?.udid ?? "no UDID"))")
        print("🚀 ========================================")
        print("")
        
        task.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                if !self.userInitiatedStop {
                    if hasStartedRecording {
                        self.onRecordingStopRequested?()
                    }
                    
                    self.isBuildingTests = false
                    self.status = hasStartedRecording ? "Auto Finised" : "Build Failed - No tests ran"
                } else {
                    self.isBuildingTests = false
                    self.userInitiatedStop = false
                }
            }
        }

        automationProcess = task
        do {
            try task.run()
        } catch {
            status = "Xcode Failed: \(error.localizedDescription)"
            isBuildingTests = false
        }
    }
    
    func stop() {
        isBuildingTests = false
        userInitiatedStop = true
        automationProcess?.terminate()
    }
}

