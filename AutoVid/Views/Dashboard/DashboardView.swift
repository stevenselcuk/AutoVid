import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct ValidationWarning: View {
    let icon: String
    let text: String
    var color: Color = AppConfig.UI.Colors.warning

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(color)
        }
    }
}

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var hoverEffect = false
    @State private var showingSettings = false
    @AppStorage(AppConfig.Configuration.StorageKeys.autoOpenEditor) private var autoOpenEditor = true

    private var isReadyToRun: Bool {
        !viewModel.projectPath.isEmpty &&
            !viewModel.schemeName.isEmpty &&
            !viewModel.detectedDevices.isEmpty
    }

    private var realDevices: [Device] {
        viewModel.availableDevices.filter { $0.type == "Real" }
    }

    private var simulators: [Device] {
        viewModel.availableDevices.filter { $0.type == "Simulator" }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(AppConfig.UI.Strings.appName).font(.system(.headline, design: .monospaced)).tracking(2)
                Spacer()


                HStack(spacing: 8) {
                    Circle().fill(viewModel.isRecording ? AppConfig.UI.Colors.recording : AppConfig.UI.Colors.success).frame(width: AppConfig.UI.Dimensions.statusDotSize, height: AppConfig.UI.Dimensions.statusDotSize).symbolEffect(.pulse, isActive: viewModel.isRecording)
                    Text(viewModel.status).font(.system(size: 10, weight: .bold, design: .monospaced))

                    if viewModel.isBuildingTests {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(AppConfig.UI.Colors.capsuleBackground))
                
                Button(action: { showingSettings = true }) {
                    Image(systemName: AppConfig.UI.Icons.settings)
                        .foregroundColor(AppConfig.UI.Colors.textSecondary)
                        .font(.system(size: AppConfig.UI.Dimensions.iconMedium))
                }
                .buttonStyle(.plain)
                .help("Settings")

            }
            .padding(25).background(AppConfig.UI.Colors.slightlyTransparent)

            ScrollView {
                VStack(spacing: 25) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("XCODE AUTOMATION", systemImage: AppConfig.UI.Icons.terminal)
                                .font(.system(size: AppConfig.UI.Dimensions.iconSmall, weight: .black))
                                .foregroundColor(AppConfig.UI.Colors.textSecondary)
                            Spacer()

                            Button(action: { viewModel.findXcodeProjects() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: AppConfig.UI.Icons.refresh)
                                    Text(AppConfig.UI.Strings.refresh)
                                }
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(AppConfig.UI.Colors.primary)
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isLoadingProjects)
                        }

                        VStack(spacing: 10) {
                            HStack {
                                Picker("Project", selection: $viewModel.projectPath) {
                                    Text("Select Project").tag("")
                                    if !viewModel.projectPath.isEmpty && viewModel.projectPath != "browse" && !viewModel.availableProjects.contains(viewModel.projectPath) {
                                        Text(URL(fileURLWithPath: viewModel.projectPath).lastPathComponent).tag(viewModel.projectPath)
                                    }
                                    ForEach(viewModel.availableProjects, id: \.self) { project in
                                        Text(URL(fileURLWithPath: project).lastPathComponent).tag(project)
                                    }
                                    Divider()
                                    Text("Browse...").tag("browse")
                                }
                                .onChange(of: viewModel.projectPath) { _, newValue in
                                    if newValue == "browse" {
                                        openFilePanel()
                                    } else {
                                        viewModel.fetchSchemes(for: newValue)
                                    }
                                }
                                .disabled(viewModel.isLoadingProjects)

                                if viewModel.isLoadingProjects {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 20, height: 20)
                                }
                            }

                            if viewModel.projectPath.isEmpty {
                                Text("Select an Xcode project or workspace")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            HStack {
                                Picker("Scheme", selection: $viewModel.schemeName) {
                                    Text(viewModel.projectPath.isEmpty ? "Select Project First" : "Select Scheme").tag("")
                                    if !viewModel.schemeName.isEmpty && !viewModel.availableSchemes.contains(viewModel.schemeName) {
                                        Text(viewModel.schemeName).tag(viewModel.schemeName)
                                    }
                                    ForEach(viewModel.availableSchemes, id: \.self) { scheme in
                                        Text(scheme).tag(scheme)
                                    }
                                }
                                .disabled(viewModel.projectPath.isEmpty || viewModel.isLoadingSchemes)

                                if viewModel.isLoadingSchemes {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 20, height: 20)
                                }
                            }

                            if !viewModel.projectPath.isEmpty && viewModel.schemeName.isEmpty && !viewModel.isLoadingSchemes {
                                Text(viewModel.availableSchemes.isEmpty ? "No schemes found" : "Select a scheme to run")
                                    .font(.system(size: 9))
                                    .foregroundColor(viewModel.availableSchemes.isEmpty ? .red : .secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            HStack {
                                Picker("Device", selection: $viewModel.deviceName) {
                                    Text("Select Device").tag("")
                                    
                                    if !viewModel.deviceName.isEmpty 
                                        && !realDevices.contains(where: { $0.name == viewModel.deviceName })
                                        && !simulators.contains(where: { $0.name == viewModel.deviceName }) {
                                        Text(viewModel.deviceName).tag(viewModel.deviceName)
                                    }

                                    if !realDevices.isEmpty {
                                        Section(header: Text("Real Devices")) {
                                            ForEach(realDevices) { device in
                                                HStack {
                                                    Image(systemName: "iphone.gen3")
                                                        .foregroundColor(device.isUSBConnected ? .green : .orange)
                                                    Text(device.name)
                                                    if device.isUSBConnected {
                                                        Image(systemName: "cable.connector")
                                                            .foregroundColor(.green)
                                                            .font(.system(size: 10))
                                                    }
                                                }.tag(device.name)
                                            }
                                        }
                                    }

                                    if !simulators.isEmpty {
                                        Section(header: Text("Simulators")) {
                                            ForEach(simulators) { device in
                                                HStack {
                                                    Image(systemName: "laptopcomputer")
                                                        .foregroundColor(.blue)
                                                    Text(device.name)
                                                }.tag(device.name)
                                            }
                                        }
                                    }
                                }
                                .disabled(viewModel.isLoadingDevices)

                                if viewModel.isLoadingDevices {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 20, height: 20)
                                }
                            }

                            if viewModel.deviceName.isEmpty {
                                Text("Select a device to run tests on")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding().background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))

                    if let device = viewModel.detectedDevices.first {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.localizedName).font(.headline)
                                Text("USB Connected").font(.system(size: 9)).foregroundColor(.blue)
                            }
                            Spacer()
                            Image(systemName: "cable.connector").foregroundColor(.green)
                        }
                        .padding().background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.05)))
                    }

                    if viewModel.isBuildingTests && !viewModel.buildOutput.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "hammer.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 10))
                                Text("Console")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                            }

                            Text(viewModel.buildOutput)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.05)))
                    }

                    if !isReadyToRun && !viewModel.isRecording {
                        VStack(alignment: .leading, spacing: 6) {
                            if viewModel.projectPath.isEmpty {
                                ValidationWarning(icon: AppConfig.UI.Icons.warning, text: "Project not selected", color: AppConfig.UI.Colors.error)
                            }
                            if viewModel.schemeName.isEmpty {
                                ValidationWarning(icon: AppConfig.UI.Icons.warning, text: "Scheme not selected - required for tests", color: AppConfig.UI.Colors.error)
                            }
                            if viewModel.detectedDevices.isEmpty {
                                ValidationWarning(icon: AppConfig.UI.Icons.warning, text: "No USB device connected - plug in your iPhone", color: AppConfig.UI.Colors.error)
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.1)))
                    }

                    Button(action: {
                        Task { viewModel.isRecording ? await viewModel.stop() : await viewModel.startWithAutomation() }
                    }) {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle().fill(viewModel.isRecording ? AppConfig.UI.Colors.recording : (isReadyToRun ? AppConfig.UI.Colors.primary : Color.gray)).frame(width: 100, height: 100).shadow(color: (viewModel.isRecording ? AppConfig.UI.Colors.recording : AppConfig.UI.Colors.primary).opacity(0.3), radius: 15)
                                Image(systemName: viewModel.isRecording ? AppConfig.UI.Icons.stop : AppConfig.UI.Icons.play).font(.system(size: AppConfig.UI.Dimensions.iconHuge)).foregroundColor(.white)
                            }
                            Text(viewModel.isRecording ? "Stop" : "Run").font(.system(size: 10, weight: .black))
                        }
                        .scaleEffect(hoverEffect ? 1.05 : 1.0).animation(.spring(), value: hoverEffect)
                    }
                    .buttonStyle(.plain).onHover { hoverEffect = $0 }
                    .disabled(!isReadyToRun && !viewModel.isRecording)

                    if let url = viewModel.lastSavedURL {
                        Button(action: { NSWorkspace.shared.open(url) }) {
                            HStack {
                                Image(systemName: "folder.fill")
                                Text(url.lastPathComponent).font(.system(size: 10, design: .monospaced)).lineLimit(1)
                                Spacer()
                                Text("Open Viode").font(.system(size: 10, weight: .bold))
                            }
                            .padding().background(Color.blue.opacity(0.1)).cornerRadius(12)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(30)
            }
        }
        .frame(width: 450, height: 650)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) {
            SettingsView(autoOpenEditor: $autoOpenEditor)
        }
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "xcodeproj")!,
            UTType(filenameExtension: "xcworkspace")!,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            if let url = panel.url {
                viewModel.projectPath = url.path
            }
        } else {
            if viewModel.projectPath == "browse" {
                viewModel.projectPath = ""
            }
        }
    }
}


struct SettingsView: View {
    @Binding var autoOpenEditor: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.blue)
                Text("Settings")
                    .font(.system(.headline, design: .monospaced))
                    .tracking(2)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color.white.opacity(0.03))

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("After Recording", systemImage: "video.fill")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.secondary)

                    Toggle(isOn: $autoOpenEditor) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Automatically open video editor")
                                .font(.system(size: 13, weight: .medium))
                            Text("When disabled, recorded videos will open in Finder instead")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))

                Spacer()
            }
            .padding(20)

            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Text("Done")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(AppConfig.UI.Colors.panelBackgroundDark)
        }
        .frame(width: 400, height: 300)
        .preferredColorScheme(.dark)
    }
}

