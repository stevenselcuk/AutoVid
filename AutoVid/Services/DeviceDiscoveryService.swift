import Foundation
import AVFoundation
import Combine

@MainActor
protocol DeviceDiscoveryServiceProtocol: AnyObject {
    var detectedDevices: [AVCaptureDevice] { get }
    var availableDevices: [Device] { get }
    var isLoadingDevices: Bool { get }
    
    var detectedDevicesPublisher: AnyPublisher<[AVCaptureDevice], Never> { get }
    var availableDevicesPublisher: AnyPublisher<[Device], Never> { get }
    var isLoadingDevicesPublisher: AnyPublisher<Bool, Never> { get }
    
    func updateDeviceList()
    func fetchAvailableDevices()
}

@MainActor
final class DeviceDiscoveryService: NSObject, ObservableObject, DeviceDiscoveryServiceProtocol {
    @Published var detectedDevices: [AVCaptureDevice] = []
    @Published var availableDevices: [Device] = []
    @Published var isLoadingDevices = false
    
    var detectedDevicesPublisher: AnyPublisher<[AVCaptureDevice], Never> { $detectedDevices.eraseToAnyPublisher() }
    var availableDevicesPublisher: AnyPublisher<[Device], Never> { $availableDevices.eraseToAnyPublisher() }
    var isLoadingDevicesPublisher: AnyPublisher<Bool, Never> { $isLoadingDevices.eraseToAnyPublisher() }
    
    private var deviceFetchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        updateDeviceList()
        fetchAvailableDevices()
        
        Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateDeviceList()
                self?.mergeDeviceLists()
            }
            .store(in: &cancellables)
    }
    
    deinit {
        deviceFetchTask?.cancel()
    }
    
    func updateDeviceList() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [AVCaptureDevice.DeviceType.external],
            mediaType: .muxed,
            position: .unspecified
        )
        let found = discovery.devices.filter {
            let name = $0.localizedName.lowercased()
            return name.contains("iphone") || name.contains("ipad") || name.contains("ios")
        }
        if detectedDevices != found {
            detectedDevices = found
        }
    }
    
    func fetchAvailableDevices() {
        deviceFetchTask?.cancel()
        deviceFetchTask = Task(priority: .userInitiated) { @MainActor in
            self.isLoadingDevices = true
            defer { self.isLoadingDevices = false }

            let fetchedDevices = await Task.detached(priority: .userInitiated) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                task.arguments = ["xctrace", "list", "devices"]

                let pipe = Pipe()
                task.standardOutput = pipe

                var devices: [Device] = []

                do {
                    try task.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        let lines = output.components(separatedBy: .newlines)
                        var currentSection = ""

                        for line in lines {
                            if line.contains("== Devices ==") { currentSection = "Devices"; continue }
                            if line.contains("== Simulators ==") { currentSection = "Simulators"; continue }
                            if line.isEmpty || line.hasPrefix("==") { continue }


                            if let udidRange = line.range(of: "\\([0-9A-Fa-f-]{24,40}\\)", options: .regularExpression, range: nil, locale: nil) {
                                let udidWithParens = String(line[udidRange])
                                let udid = udidWithParens.dropFirst().dropLast()

                                let beforeUDID = String(line[..<udidRange.lowerBound]).trimmingCharacters(in: .whitespaces)

                                let name = beforeUDID.replacingOccurrences(of: "\\s*\\([0-9.]+\\)\\s*$", with: "", options: .regularExpression)

                                let isIOSDevice = name.lowercased().contains("iphone") ||
                                    name.lowercased().contains("ipad") ||
                                    line.lowercased().contains("ios")

                                if currentSection == "Devices" && !isIOSDevice {
                                    continue
                                }

                                devices.append(Device(name: name, udid: String(udid), type: currentSection == "Devices" ? "Real" : "Simulator", isUSBConnected: false))
                            } else {
                                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                                }
                            }
                        }
                    }
                } catch {
                    print("❌ [xctrace] Failed to fetch devices: \(error)")
                }

                return devices
            }.value

            self.availableDevices = fetchedDevices
            self.mergeDeviceLists()
        }
    }
    
    private func mergeDeviceLists() {
        let usbDeviceNames = Set(detectedDevices.map { $0.localizedName })

        availableDevices = availableDevices.map { device in
            let isConnected = usbDeviceNames.contains(device.name) ||
                usbDeviceNames.contains(where: { $0.contains(device.name) || device.name.contains($0) })

            if isConnected {
            }

            return Device(
                name: device.name,
                udid: device.udid,
                type: device.type,
                isUSBConnected: isConnected
            )
        }

    }
}

