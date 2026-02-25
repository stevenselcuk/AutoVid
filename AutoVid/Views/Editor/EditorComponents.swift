import SwiftUI

struct ExportSettingsView: View {
    @ObservedObject var engine: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(AppConfig.UI.Strings.resolution)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 80, alignment: .leading)

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
                            .frame(width: 80)
                        TextField("Width", text: $engine.customWidth)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("×")
                        TextField("Height", text: $engine.customHeight)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }
                }

                HStack {
                    Text(AppConfig.UI.Strings.frameRate)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 80, alignment: .leading)

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
                        .frame(width: 80, alignment: .leading)

                    Picker("", selection: $engine.selectedBitrate) {
                        Text("Low (8 Mbps)").tag(8000000)
                        Text("Medium (16 Mbps)").tag(16000000)
                        Text("High (24 Mbps)").tag(24000000)
                    }
                    .labelsHidden()
                }
            }
        }
        .padding()
        .frame(width: 300)
    }
}


struct TransportControls: View {
    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onSeekStart: () -> Void
    let onSeekEnd: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            Button(action: onSeekStart) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Button(action: onPlayPause) {
                ZStack {
                    Circle()
                        .fill(AppConfig.UI.Colors.primary)
                        .frame(width: 44, height: 44)
                        .shadow(color: AppConfig.UI.Colors.primary.opacity(0.4), radius: 8, y: 4)

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)

            Button(action: onSeekEnd) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

struct TimeDisplay: View {
    let currentTime: Double
    let duration: Double

    var body: some View {
        HStack(spacing: 4) {
            Text(formatTime(currentTime))
                .foregroundColor(.white)
            Text("/")
                .foregroundColor(.secondary)
            Text(formatTime(duration))
                .foregroundColor(.secondary)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.3)))
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", mins, secs, millis)
    }
}
