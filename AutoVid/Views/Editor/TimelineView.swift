import SwiftUI
import AppKit

fileprivate func tickIntervals(for duration: Double) -> (major: Double, minor: Double) {
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
    @State private var lastSnappedTime: Double? = nil

    private let handleWidth: CGFloat = 24.0
    private let halfHandle: CGFloat = 12.0

    enum TimelineElement {
        case playhead
        case startHandle
        case endHandle
    }

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            ZStack(alignment: .leading) {
                // Background Track
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))

                    TimelineTicksView(duration: engine.duration, width: trackWidth(for: w))
                }
                .frame(width: trackWidth(for: w))
                .offset(x: halfHandle)

                // Left Dark Track Mask
                let sOffsetX = timeToX(engine.trimStart, in: w)
                if sOffsetX > halfHandle {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: sOffsetX - halfHandle)
                        .offset(x: halfHandle)
                }

                // Right Dark Track Mask
                let eOffsetX = timeToX(engine.trimEnd, in: w)
                if eOffsetX < w - halfHandle {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: w - halfHandle - eOffsetX)
                        .offset(x: eOffsetX)
                }

                // Trimmed Blue Region
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.25))
                    .frame(width: max(0, eOffsetX - sOffsetX))
                    .offset(x: sOffsetX)

                // Limit Line (30s)
                if engine.duration > 30 {
                    let limitX = timeToX(30, in: w)
                    if limitX < w - halfHandle {
                        Rectangle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: max(0, w - halfHandle - limitX))
                            .offset(x: limitX)

                        Rectangle()
                            .fill(Color.orange.opacity(0.6))
                            .frame(width: 2)
                            .offset(x: limitX)
                    }
                }

                // Playhead
                ZStack {
                    Rectangle()
                        .fill(engine.isPlaying ? Color.green : Color.white)
                        .frame(width: 3, height: 60)
                        .shadow(color: .black.opacity(0.5), radius: 2)

                    Circle()
                        .fill(engine.isPlaying ? Color.green : Color.white)
                        .frame(width: 12, height: 12)
                        .offset(y: -24)
                        .shadow(color: .black.opacity(0.3), radius: 3)
                }
                .contentShape(Rectangle())
                .frame(width: 24, height: 60)
                .position(x: timeToX(engine.currentTime, in: w), y: 30)
                .scaleEffect(isDraggingPlayhead ? 1.1 : (hoveredElement == .playhead ? 1.05 : 1.0))
                .animation(.spring(response: 0.2), value: isDraggingPlayhead)
                .animation(.spring(response: 0.2), value: hoveredElement)
                .onHover { hovering in
                    hoveredElement = hovering ? .playhead : nil
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("TimelineSpace"))
                        .onChanged { value in
                            isDraggingPlayhead = true
                            let position = max(halfHandle, min(value.location.x, w - halfHandle))
                            let time = getSnappedTime(for: position, width: w)
                            engine.seek(to: time)

                            tooltipTime = time
                            tooltipPosition = CGPoint(x: timeToX(time, in: w), y: -20)
                            showTooltip = true
                        }
                        .onEnded { _ in
                            isDraggingPlayhead = false
                            showTooltip = false
                            lastSnappedTime = nil
                        }
                )

                // Start Handle
                EnhancedTrimHandle(
                    isStart: true,
                    isActive: isDraggingStart,
                    isHovered: hoveredElement == .startHandle
                )
                .position(x: timeToX(engine.trimStart, in: w), y: 30)
                .onHover { hovering in
                    hoveredElement = hovering ? .startHandle : nil
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("TimelineSpace"))
                        .onChanged { value in
                            isDraggingStart = true
                            let position = max(halfHandle, min(value.location.x, w - halfHandle))
                            let time = getSnappedTime(for: position, width: w)
                            engine.updateTrimStart(time)

                            tooltipTime = time
                            tooltipPosition = CGPoint(x: timeToX(time, in: w), y: -20)
                            showTooltip = true
                        }
                        .onEnded { _ in
                            isDraggingStart = false
                            showTooltip = false
                            lastSnappedTime = nil
                        }
                )

                // End Handle
                EnhancedTrimHandle(
                    isStart: false,
                    isActive: isDraggingEnd,
                    isHovered: hoveredElement == .endHandle
                )
                .position(x: timeToX(engine.trimEnd, in: w), y: 30)
                .onHover { hovering in
                    hoveredElement = hovering ? .endHandle : nil
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("TimelineSpace"))
                        .onChanged { value in
                            isDraggingEnd = true
                            let position = max(halfHandle, min(value.location.x, w - halfHandle))
                            let time = getSnappedTime(for: position, width: w)
                            engine.updateTrimEnd(time)

                            tooltipTime = time
                            tooltipPosition = CGPoint(x: timeToX(time, in: w), y: -20)
                            showTooltip = true
                        }
                        .onEnded { _ in
                            isDraggingEnd = false
                            showTooltip = false
                            lastSnappedTime = nil
                        }
                )

                if showTooltip {
                    TimelineTooltip(time: tooltipTime, position: tooltipPosition)
                }
            }
            .coordinateSpace(name: "TimelineSpace")
            .frame(height: 60)
        }
        .frame(height: 60)
    }

    private func trackWidth(for width: CGFloat) -> CGFloat {
        return max(0, width - handleWidth)
    }

    private func timeToX(_ time: Double, in width: CGFloat) -> CGFloat {
        guard engine.duration > 0 else { return halfHandle }
        return halfHandle + (time / engine.duration) * trackWidth(for: width)
    }

    private func xToTime(_ x: CGFloat, in width: CGFloat) -> Double {
        guard engine.duration > 0 else { return 0 }
        let clampedX = max(halfHandle, min(x, width - halfHandle))
        return ((clampedX - halfHandle) / trackWidth(for: width)) * engine.duration
    }

    private func getSnappedTime(for position: CGFloat, width: CGFloat) -> Double {
        guard engine.duration > 0 else { return 0 }
        let rawTime = xToTime(position, in: width)
        let minorInterval = tickIntervals(for: engine.duration).minor
        let nearestTick = round(rawTime / minorInterval) * minorInterval
        let tickPixelX = timeToX(nearestTick, in: width)
        let snapThresholdPx: CGFloat = 8.0

        if abs(position - tickPixelX) <= snapThresholdPx {
            if lastSnappedTime != nearestTick {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                lastSnappedTime = nearestTick
            }
            return nearestTick
        }
        
        lastSnappedTime = nil
        return rawTime
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
        .contentShape(Rectangle())
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

