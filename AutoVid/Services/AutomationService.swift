import Foundation
import Observation

@MainActor
protocol AutomationServiceProtocol: AnyObject {
    var isBuildingTests: Bool { get }
    var buildOutput: String { get }
    var status: String { get }
    
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
@Observable
final class AutomationService: AutomationServiceProtocol {
    var isBuildingTests = false
    var buildOutput: String = ""
    var status = "IDLE"
    
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

        automationProcess = task
        
        do {
            try task.run()
        } catch {
            status = "Xcode Failed: \(error.localizedDescription)"
            isBuildingTests = false
            return
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

        var hasStartedRecording = false

        do {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                if userInitiatedStop { break }
                
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
        } catch {
            print("Stream Error: \(error.localizedDescription)")
        }
        
        if !userInitiatedStop {
            if hasStartedRecording {
                onRecordingStopRequested?()
            }
            status = hasStartedRecording ? "Auto Finised" : "Build Failed - No tests ran"
        } else {
            status = "Stopped by User"
            userInitiatedStop = false
        }
        
        isBuildingTests = false
        automationProcess = nil
    }
    
    func stop() {
        isBuildingTests = false
        userInitiatedStop = true
        automationProcess?.terminate()
    }
}
