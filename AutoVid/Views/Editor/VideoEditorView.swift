import SwiftUI
import AVFoundation


struct EditorView: View {
    @StateObject private var engine: EditorViewModel
    @State private var showingExportSettings = false
    @Environment(\.dismiss) private var dismiss

    init(videoURL: URL) {
        _engine = StateObject(wrappedValue: EditorViewModel(videoURL: videoURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(AppConfig.UI.Strings.editorTitle)
                    .font(.system(.headline, design: .monospaced))
                    .tracking(2)
                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(AppConfig.UI.Strings.exportTitle, systemImage: AppConfig.UI.Icons.settings)
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(AppConfig.UI.Colors.textSecondary)
                        Spacer()
                        Button(action: { showingExportSettings.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: showingExportSettings ? AppConfig.UI.Icons.chevronUp : AppConfig.UI.Icons.chevronDown)
                                Text(showingExportSettings ? "HIDE" : "SHOW")
                            }
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AppConfig.UI.Colors.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    if showingExportSettings {
                        VStack(spacing: 12) {
                            HStack {
                                Text(AppConfig.UI.Strings.resolution)
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(width: 100, alignment: .leading)

                                Picker("", selection: $engine.selectedResolution) {
                                    ForEach(ExportSettings.Resolution.allCases, id: \.self) { res in
                                        Text("\(res.rawValue) (\(res.description))").tag(res)
                                    }
                                }
                                .labelsHidden()
                            }

                            if engine.selectedResolution == .custom {
                                HStack {
                                    Text("")
                                        .frame(width: 100)
                                    TextField("Width", text: $engine.customWidth)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                    Text("×")
                                    TextField("Height", text: $engine.customHeight)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                }
                            }

                            HStack {
                                Text(AppConfig.UI.Strings.frameRate)
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(width: 100, alignment: .leading)

                                Picker("", selection: $engine.selectedFrameRate) {
                                    Text("24 fps").tag(24)
                                    Text("30 fps").tag(30)
                                    Text("60 fps").tag(60)
                                }
                                .labelsHidden()
                            }

                            HStack {
                                Text(AppConfig.UI.Strings.bitrate)
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(width: 100, alignment: .leading)

                                Picker("", selection: $engine.selectedBitrate) {
                                    Text("Low (8 Mbps)").tag(8000000)
                                    Text("Medium (16 Mbps)").tag(16000000)
                                    Text("High (24 Mbps)").tag(24000000)
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(AppConfig.UI.Colors.panelBackground))
                Button(action: {
                    engine.exportVideo { result in
                        switch result {
                        case let .success(url):
                            print("✅ Exported to: \(url.path)")
                        case let .failure(error):
                            print("❌ Export failed: \(error)")
                        }
                    }
                }) {
                    HStack(spacing: 12) {
                        if engine.isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 20, height: 20)
                            Text("Exporting... \(Int(engine.exportProgress * 100))%")
                                .font(.system(size: 12, weight: .black))
                        } else {
                            HStack {
                                Image(systemName: engine.exceedsAppStoreLimit ? AppConfig.UI.Icons.warning : AppConfig.UI.Icons.export)
                                    .font(.system(size: 16))
                                Text(AppConfig.UI.Strings.exportButton)
                                    .font(.system(size: 12, weight: .black))
                            }
                           
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: 220)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(engine.isExporting ? Color.gray : (engine.exceedsAppStoreLimit ? AppConfig.UI.Colors.warning : AppConfig.UI.Colors.primary))
                    )
                }
                .buttonStyle(.plain)
                .disabled(engine.isExporting)

                Button(action: { dismiss() }) {
                    Image(systemName: AppConfig.UI.Icons.close)
                        .font(.system(size: 16))
                        .foregroundColor(AppConfig.UI.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
            }
            .padding(25)
            .background(AppConfig.UI.Colors.slightlyTransparent)

            ScrollView {
                VStack(spacing: 25) {
                    if let player = engine.player {
                        VideoPlayerView(player: player)
                            .aspectRatio(engine.videoAspectRatio, contentMode: .fit)
                            .frame(
                                maxWidth: engine.videoAspectRatio < 1.0 ? 400 : 700,
                                maxHeight: engine.videoAspectRatio < 1.0 ? 600 : 500
                            )
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }

                    HStack(spacing: 20) {
                        Button(action: { engine.seekToStart() }) {
                            Image(systemName: "backward.end.fill")
                                .font(.system(size: 20))
                        }
                        .buttonStyle(.plain)

                        Button(action: { engine.togglePlayPause() }) {
                            ZStack {
                                Circle()
                                    .fill(Color.gray)
                                    .frame(width: 50, height: 50)
                                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)

                        Button(action: { engine.seekToEnd() }) {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 20))
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        TimelineView(engine: engine)

                        HStack {
                            Text(formatTime(engine.trimStart))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatTime(engine.trimEnd))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))

                    if let error = engine.exportError {
                        HStack(spacing: 8) {
                             Image(systemName: AppConfig.UI.Icons.error)
                                .foregroundColor(AppConfig.UI.Colors.error)
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundColor(AppConfig.UI.Colors.error)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(AppConfig.UI.Colors.errorBackground))
                    }

                    if let url = engine.lastExportedURL {
                        Button(action: { NSWorkspace.shared.open(url) }) {
                            HStack {
                                Image(systemName: AppConfig.UI.Icons.success)
                                    .foregroundColor(AppConfig.UI.Colors.success)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Exported Successfully")
                                        .font(.system(size: 10, weight: .bold))
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 9, design: .monospaced))
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("OPEN")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding()
                            .background(AppConfig.UI.Colors.successBackground)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(30)
            }
        }
        .frame(width: AppConfig.UI.Dimensions.editorWindowWidth, height: AppConfig.UI.Dimensions.editorWindowHeight)
        .preferredColorScheme(.dark)
        .onDisappear {
            engine.cleanup()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, millis)
    }
}

