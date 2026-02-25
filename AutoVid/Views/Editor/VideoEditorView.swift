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
            // Header / Toolbar
            HStack(spacing: 16) {
                Text(AppConfig.UI.Strings.editorTitle)
                    .font(.system(.headline, design: .monospaced))
                    .tracking(2)

                Spacer()

                // Export Settings Button
                Button(action: { showingExportSettings.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: AppConfig.UI.Icons.settings)
                        Text("Export Settings")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppConfig.UI.Colors.capsuleBackground)
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingExportSettings) {
                    ExportSettingsView(engine: engine)
                }

                // Export Button
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
                    HStack(spacing: 8) {
                        if engine.isExporting {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                            Text("Exporting... \(Int(engine.exportProgress * 100))%")
                        } else {
                            Image(systemName: engine.exceedsAppStoreLimit ? AppConfig.UI.Icons.warning : AppConfig.UI.Icons.export)
                            Text(AppConfig.UI.Strings.exportButton)
                        }
                    }
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 140)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(engine.isExporting ? Color.gray : (engine.exceedsAppStoreLimit ? AppConfig.UI.Colors.warning : AppConfig.UI.Colors.primary))
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(engine.isExporting)

                // Close Button
                Button(action: { dismiss() }) {
                    Image(systemName: AppConfig.UI.Icons.close)
                        .font(.system(size: 16))
                        .foregroundColor(AppConfig.UI.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(AppConfig.UI.Colors.slightlyTransparent)

            // Main Content
            VStack(spacing: 20) {
                // Video Player Area
                ZStack {
                    if let player = engine.player {
                        GeometryReader { geometry in
                            ZStack {
                                Color.black.opacity(0.3) // Letterbox background
                                
                                VideoPlayerView(player: player)
                                    .aspectRatio(engine.videoAspectRatio, contentMode: .fit)
                                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                                    .cornerRadius(12)
                                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                            }
                        }
                    } else {
                        ZStack {
                            Color.black.opacity(0.2)
                            ProgressView()
                        }
                        .cornerRadius(12)
                    }

                    // Floating Controls Overlay (Optional, or can be below)
                }
                .frame(minHeight: 300)

                // Transport Controls & Time
                HStack {
                    TimeDisplay(currentTime: engine.currentTime, duration: engine.duration)
                    Spacer()
                    TransportControls(
                        isPlaying: engine.isPlaying,
                        onPlayPause: { engine.togglePlayPause() },
                        onSeekStart: { engine.seekToStart() },
                        onSeekEnd: { engine.seekToEnd() }
                    )
                    Spacer()
                    // Balance the TimeDisplay
                    TimeDisplay(currentTime: engine.currentTime, duration: engine.duration)
                        .opacity(0) // Invisible, just for layout balance
                }
                .padding(.horizontal)

                // Timeline Area
                VStack(spacing: 12) {
                    TimelineView(engine: engine)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(formatTime(engine.trimStart))
                                .font(.system(size: 11, design: .monospaced))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("End")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(formatTime(engine.trimEnd))
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 16).fill(AppConfig.UI.Colors.panelBackground))

                // Errors & Success
                if let error = engine.exportError {
                    HStack(spacing: 8) {
                         Image(systemName: AppConfig.UI.Icons.error)
                            .foregroundColor(AppConfig.UI.Colors.error)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(AppConfig.UI.Colors.error)
                        Spacer()
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
                                Text("Export Successful")
                                    .font(.system(size: 11, weight: .bold))
                                Text(url.lastPathComponent)
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineLimit(1)
                                    .opacity(0.8)
                            }
                            Spacer()
                            Text("OPEN")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().stroke(Color.white.opacity(0.2)))
                        }
                        .padding()
                        .background(AppConfig.UI.Colors.successBackground)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
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
