import SwiftUI


struct TimelineTicksView: View {
    let duration: Double
    let width: CGFloat
    let height: CGFloat = 60

    var body: some View {
        Canvas { context, size in
            guard duration > 0 else { return }

            let (majorInterval, minorInterval) = tickIntervals(for: duration)

            var time: Double = 0
            while time <= duration {
                let x = (time / duration) * size.width

                let isMinor = time.truncatingRemainder(dividingBy: majorInterval) != 0

                if isMinor {
                    let tickHeight: CGFloat = 6
                    let path = Path { p in
                        p.move(to: CGPoint(x: x, y: size.height - tickHeight))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    context.stroke(path, with: .color(.white.opacity(0.2)), lineWidth: 1)
                }

                time += minorInterval
            }

            time = 0
            while time <= duration {
                let x = (time / duration) * size.width

                let tickHeight: CGFloat = 12
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: size.height - tickHeight))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(path, with: .color(.white.opacity(0.4)), lineWidth: 1.5)

                let timeText = formatTickTime(time)
                let textPosition = CGPoint(x: x, y: size.height - 18)
                context.draw(Text(timeText)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6)),
                    at: textPosition)

                time += majorInterval
            }
        }
        .frame(height: height)
    }

    private func tickIntervals(for duration: Double) -> (major: Double, minor: Double) {
        switch duration {
        case 0 ..< 10:
            return (1.0, 0.1)
        case 10 ..< 30:
            return (2.0, 0.5)
        case 30 ..< 60:
            return (5.0, 1.0)
        case 60 ..< 180:
            return (10.0, 2.0)
        default:
            return (30.0, 5.0)
        }
    }

    private func formatTickTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return String(format: "%d:%02d", mins, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }
}


struct TimelineTooltip: View {
    let time: Double
    let position: CGPoint

    var body: some View {
        Text(formatTime(time))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.8))
                    .shadow(color: .black.opacity(0.3), radius: 4)
            )
            .foregroundColor(.white)
            .position(position)
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", mins, secs, millis)
    }
}


struct TimelineView: View {
    @ObservedObject var engine: EditorViewModel
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var isDraggingPlayhead = false
    @State private var hoveredElement: TimelineElement? = nil
    @State private var tooltipPosition: CGPoint = .zero
    @State private var tooltipTime: Double = 0
    @State private var showTooltip: Bool = false

    enum TimelineElement {
        case playhead
        case startHandle
        case endHandle
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))

                    TimelineTicksView(duration: engine.duration, width: geometry.size.width)
                }

                if trimStartOffset(in: geometry.size.width) > 0 {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: trimStartOffset(in: geometry.size.width))
                }

                let rightOffset = trimEndOffset(in: geometry.size.width)
                if rightOffset < geometry.size.width {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: geometry.size.width - rightOffset)
                        .offset(x: rightOffset)
                }

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.25))
                    .frame(width: trimmedWidth(in: geometry.size.width))
                    .offset(x: trimStartOffset(in: geometry.size.width))

                if engine.duration > 30 {
                    let limitX = (30.0 / engine.duration) * geometry.size.width

                    Rectangle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: geometry.size.width - limitX)
                        .offset(x: limitX)

                    Rectangle()
                        .fill(Color.orange.opacity(0.6))
                        .frame(width: 2)
                        .offset(x: limitX)
                }

                ZStack {
                    Rectangle()
                        .fill(engine.isPlaying ? Color.green : Color.white)
                        .frame(width: 3)
                        .shadow(color: .black.opacity(0.5), radius: 2)

                    Circle()
                        .fill(engine.isPlaying ? Color.green : Color.white)
                        .frame(width: 12, height: 12)
                        .offset(y: -24)
                        .shadow(color: .black.opacity(0.3), radius: 3)
                }
                .offset(x: playheadOffset(in: geometry.size.width))
                .scaleEffect(isDraggingPlayhead ? 1.1 : (hoveredElement == .playhead ? 1.05 : 1.0))
                .animation(.spring(response: 0.2), value: isDraggingPlayhead)
                .animation(.spring(response: 0.2), value: hoveredElement)
                .onHover { hovering in
                    hoveredElement = hovering ? .playhead : nil
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDraggingPlayhead = true
                            let position = max(0, min(value.location.x, geometry.size.width))
                            let time = (position / geometry.size.width) * engine.duration
                            engine.seek(to: time)

                            tooltipTime = time
                            tooltipPosition = CGPoint(x: position, y: -20)
                            showTooltip = true
                        }
                        .onEnded { _ in
                            isDraggingPlayhead = false
                            showTooltip = false
                        }
                )

                EnhancedTrimHandle(
                    isStart: true,
                    isActive: isDraggingStart,
                    isHovered: hoveredElement == .startHandle
                )
                .offset(x: trimStartOffset(in: geometry.size.width) - 12)
                .onHover { hovering in
                    hoveredElement = hovering ? .startHandle : nil
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDraggingStart = true
                            let position = max(0, min(value.location.x, geometry.size.width))
                            let time = (position / geometry.size.width) * engine.duration
                            engine.updateTrimStart(time)

                            tooltipTime = time
                            tooltipPosition = CGPoint(x: position, y: -20)
                            showTooltip = true
                        }
                        .onEnded { _ in
                            isDraggingStart = false
                            showTooltip = false
                        }
                )

                EnhancedTrimHandle(
                    isStart: false,
                    isActive: isDraggingEnd,
                    isHovered: hoveredElement == .endHandle
                )
                .offset(x: trimEndOffset(in: geometry.size.width) - 12)
                .onHover { hovering in
                    hoveredElement = hovering ? .endHandle : nil
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDraggingEnd = true
                            let position = max(0, min(value.location.x, geometry.size.width))
                            let time = (position / geometry.size.width) * engine.duration
                            engine.updateTrimEnd(time)

                            tooltipTime = time
                            tooltipPosition = CGPoint(x: position, y: -20)
                            showTooltip = true
                        }
                        .onEnded { _ in
                            isDraggingEnd = false
                            showTooltip = false
                        }
                )

                if showTooltip {
                    TimelineTooltip(time: tooltipTime, position: tooltipPosition)
                }
            }
            .frame(height: 60)
        }
        .frame(height: 60)
    }

    private func trimStartOffset(in width: CGFloat) -> CGFloat {
        guard engine.duration > 0 else { return 0 }
        return (engine.trimStart / engine.duration) * width
    }

    private func trimEndOffset(in width: CGFloat) -> CGFloat {
        guard engine.duration > 0 else { return 0 }
        return (engine.trimEnd / engine.duration) * width
    }

    private func trimmedWidth(in width: CGFloat) -> CGFloat {
        let width = trimEndOffset(in: width) - trimStartOffset(in: width)
        return max(0, width)
    }

    private func playheadOffset(in width: CGFloat) -> CGFloat {
        guard engine.duration > 0 else { return 0 }
        return (engine.currentTime / engine.duration) * width
    }
}

struct EnhancedTrimHandle: View {
    let isStart: Bool
    let isActive: Bool
    let isHovered: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color.white.opacity(0.85),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 24, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.blue.opacity(isActive ? 0.8 : 0.3), lineWidth: isActive ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.4), radius: isActive ? 6 : 4)
                .shadow(color: .blue.opacity(isHovered ? 0.5 : 0), radius: isHovered ? 8 : 0)

            VStack(spacing: 3) {
                ForEach(0 ..< 4) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 3, height: 14)
                }
            }

            Image(systemName: isStart ? "chevron.left" : "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.blue.opacity(0.6))
                .offset(y: -22)
        }
        .scaleEffect(isActive ? 1.1 : (isHovered ? 1.05 : 1.0))
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isActive)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
    }
}

struct TrimHandle: View {
    let isStart: Bool

    var body: some View {
        EnhancedTrimHandle(isStart: isStart, isActive: false, isHovered: false)
    }
}

