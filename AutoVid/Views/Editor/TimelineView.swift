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
                    let tickHeight: CGFloat = 4
                    let path = Path { p in
                        p.move(to: CGPoint(x: x, y: size.height - tickHeight))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    context.stroke(path, with: .color(Color.white.opacity(0.15)), lineWidth: 1)
                }

                time += minorInterval
            }

            time = 0
            while time <= duration {
                let x = (time / duration) * size.width

                let tickHeight: CGFloat = 8
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: size.height - tickHeight))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(path, with: .color(Color.white.opacity(0.3)), lineWidth: 1.5)

                let timeText = formatTickTime(time)
                let textPosition = CGPoint(x: x, y: size.height - 14)
                context.draw(Text(timeText)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4)),
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
                    .fill(AppConfig.UI.Colors.primary)
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
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.2))

                    TimelineTicksView(duration: engine.duration, width: trackWidth(for: w))
                }
                .frame(width: trackWidth(for: w))
                .offset(x: halfHandle)

                // Left Dark Track Mask
                let sOffsetX = timeToX(engine.trimStart, in: w)
                if sOffsetX > halfHandle {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.5))
                        .frame(width: sOffsetX - halfHandle)
                        .offset(x: halfHandle)
                }

                // Right Dark Track Mask
                let eOffsetX = timeToX(engine.trimEnd, in: w)
                if eOffsetX < w - halfHandle {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.5))
                        .frame(width: w - halfHandle - eOffsetX)
                        .offset(x: eOffsetX)
                }

                // Trimmed Active Region
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppConfig.UI.Colors.primary.opacity(0.15))
                    .frame(width: max(0, eOffsetX - sOffsetX))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppConfig.UI.Colors.primary.opacity(0.3), lineWidth: 1)
                    )
                    .offset(x: sOffsetX)

                // Limit Line (30s)
                if engine.duration > 30 {
                    let limitX = timeToX(30, in: w)
                    if limitX < w - halfHandle {
                        Rectangle()
                            .fill(AppConfig.UI.Colors.warning.opacity(0.1))
                            .frame(width: max(0, w - halfHandle - limitX))
                            .offset(x: limitX)

                        Rectangle()
                            .fill(AppConfig.UI.Colors.warning)
                            .frame(width: 1)
                            .offset(x: limitX)
                    }
                }

                // Playhead
                ZStack {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 60)
                        .shadow(color: .black.opacity(0.5), radius: 1)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .offset(y: -28)
                        .shadow(color: .black.opacity(0.3), radius: 2)

                    if isDraggingPlayhead {
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 4)
                            .frame(width: 18, height: 18)
                            .offset(y: -28)
                    }
                }
                .contentShape(Rectangle())
                .frame(width: 24, height: 60)
                .position(x: timeToX(engine.currentTime, in: w), y: 30)
                .scaleEffect(isDraggingPlayhead ? 1.0 : (hoveredElement == .playhead ? 1.0 : 1.0))
                .animation(.spring(response: 0.2), value: isDraggingPlayhead)
                .zIndex((hoveredElement == .playhead || isDraggingPlayhead) ? 20 : 10)
                .onHover { hovering in
                    hoveredElement = hovering ? .playhead : nil
                }

                // Start Handle
                EnhancedTrimHandle(
                    isStart: true,
                    isActive: isDraggingStart,
                    isHovered: hoveredElement == .startHandle
                )
                .position(x: timeToX(engine.trimStart, in: w), y: 30)
                .zIndex((hoveredElement == .startHandle || isDraggingStart) ? 15 : 5)
                .onHover { hovering in
                    hoveredElement = hovering ? .startHandle : nil
                }

                // End Handle
                EnhancedTrimHandle(
                    isStart: false,
                    isActive: isDraggingEnd,
                    isHovered: hoveredElement == .endHandle
                )
                .position(x: timeToX(engine.trimEnd, in: w), y: 30)
                .zIndex((hoveredElement == .endHandle || isDraggingEnd) ? 15 : 5)
                .onHover { hovering in
                    hoveredElement = hovering ? .endHandle : nil
                }

                if showTooltip {
                    TimelineTooltip(time: tooltipTime, position: tooltipPosition)
                        .zIndex(30)
                }
            }
            .contentShape(Rectangle())
            .coordinateSpace(name: "TimelineSpace")
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("TimelineSpace"))
                    .onChanged { value in
                        let position = max(halfHandle, min(value.location.x, w - halfHandle))
                        let time = getSnappedTime(for: position, width: w)

                        if !isDraggingStart && !isDraggingEnd && !isDraggingPlayhead {
                            let startX = timeToX(engine.trimStart, in: w)
                            let endX = timeToX(engine.trimEnd, in: w)
                            let headX = timeToX(engine.currentTime, in: w)
                            
                            let distStart = abs(value.startLocation.x - startX)
                            let distEnd = abs(value.startLocation.x - endX)
                            let distHead = abs(value.startLocation.x - headX)
                            
                            let handleHitArea: CGFloat = 30.0
                            
                            if distStart < handleHitArea && distStart <= distEnd && distStart <= distHead {
                                isDraggingStart = true
                            } else if distEnd < handleHitArea && distEnd <= distHead {
                                isDraggingEnd = true
                            } else {
                                isDraggingPlayhead = true
                            }
                        }

                        if isDraggingStart {
                            engine.updateTrimStart(time)
                        } else if isDraggingEnd {
                            engine.updateTrimEnd(time)
                        } else if isDraggingPlayhead {
                            engine.seek(to: time)
                        }

                        tooltipTime = time
                        tooltipPosition = CGPoint(x: timeToX(time, in: w), y: -20)
                        showTooltip = true
                    }
                    .onEnded { _ in
                        isDraggingStart = false
                        isDraggingEnd = false
                        isDraggingPlayhead = false
                        showTooltip = false
                        lastSnappedTime = nil
                    }
            )
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
                .fill(AppConfig.UI.Colors.primary)
                .frame(width: 14, height: 40) // Slimmer handle
                .shadow(color: AppConfig.UI.Colors.primary.opacity(0.5), radius: isActive ? 6 : 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )

            VStack(spacing: 2) {
                ForEach(0 ..< 3) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 2, height: 2)
                }
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(isActive ? 1.1 : (isHovered ? 1.05 : 1.0))
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isActive)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
    }
}
