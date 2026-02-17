import SwiftUI

struct FloatingOverlayLayoutMetrics: Equatable {
    let size: CGSize
    let pillCenterY: CGFloat
}

struct FloatingOverlayView: View {
    private enum OverlayLayout {
        static let coordinateSpaceName = "FloatingOverlayRoot"
        static let outerHorizontalPadding: CGFloat = 8
        static let outerVerticalPadding: CGFloat = 6
        static let tooltipWidth: CGFloat = 320
        static let tooltipHeight: CGFloat = 44
        static let tooltipGap: CGFloat = 8
        static let fixedWidth: CGFloat = tooltipWidth + (outerHorizontalPadding * 2)
    }

    @ObservedObject var state: AppState
    var onLayoutChange: (FloatingOverlayLayoutMetrics) -> Void
    var onDragChanged: (CGSize) -> Void
    var onDragEnded: () -> Void

    @State private var isHovering = false
    @State private var isDragging = false
    @State private var rootSize: CGSize = .zero
    @State private var pillFrame: CGRect = .zero

    var body: some View {
        Group {
            if shouldShowHoverTip {
                if state.overlayTooltipDirection == .above {
                    VStack(spacing: OverlayLayout.tooltipGap) {
                        hoverTip
                            .frame(width: OverlayLayout.tooltipWidth, height: OverlayLayout.tooltipHeight)
                        measuredOverlayPill
                    }
                    .transition(.opacity)
                } else {
                    VStack(spacing: OverlayLayout.tooltipGap) {
                        measuredOverlayPill
                        hoverTip
                            .frame(width: OverlayLayout.tooltipWidth, height: OverlayLayout.tooltipHeight)
                    }
                    .transition(.opacity)
                }
            } else {
                measuredOverlayPill
            }
        }
        .padding(.horizontal, OverlayLayout.outerHorizontalPadding)
        .padding(.vertical, OverlayLayout.outerVerticalPadding)
        .frame(width: OverlayLayout.fixedWidth, alignment: .center)
        .fixedSize()
        .coordinateSpace(name: OverlayLayout.coordinateSpaceName)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: OverlayRootSizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(OverlayRootSizePreferenceKey.self) { size in
            rootSize = size
            emitLayoutMetricsIfReady()
        }
        .onPreferenceChange(OverlayPillFramePreferenceKey.self) { frame in
            pillFrame = frame
            emitLayoutMetricsIfReady()
        }
        .onHover { hovering in
            guard state.visualState == .idle, !isDragging else {
                isHovering = false
                return
            }
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovering = hovering
            }
        }
        .onChange(of: state.visualState) { _, visualState in
            if visualState != .idle {
                isHovering = false
            }
        }
        .simultaneousGesture(overlayDragGesture)
    }

    private var shouldShowHoverTip: Bool {
        state.visualState == .idle && isHovering
    }

    private var hoverTip: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.black)
            Text("Click or hold fn to start dictating")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .padding(.horizontal, 18)
        }
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var measuredOverlayPill: some View {
        overlayPill
            .contentShape(Rectangle())
            .onTapGesture(perform: handleTap)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: OverlayPillFramePreferenceKey.self,
                            value: proxy.frame(in: .named(OverlayLayout.coordinateSpaceName))
                        )
                }
            )
    }

    private func emitLayoutMetricsIfReady() {
        guard rootSize.width > 0, rootSize.height > 0, pillFrame.width > 0, pillFrame.height > 0 else {
            return
        }
        onLayoutChange(
            FloatingOverlayLayoutMetrics(
                size: rootSize,
                pillCenterY: pillFrame.midY
            )
        )
    }

    @ViewBuilder
    private var overlayPill: some View {
        switch state.visualState {
        case .idle:
            if isHovering {
                Capsule(style: .continuous)
                    .fill(.black)
                    .frame(width: 90, height: 28)
                    .overlay(
                        Text("··········")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.78))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            } else {
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 40, height: 8)
            }

        case .recording:
            Capsule(style: .continuous)
                .fill(.black)
                .frame(width: 74, height: 30)
                .overlay(
                    AudioWaveformView(level: state.recordingAudioLevel)
                        .frame(height: 16)
                        .padding(.horizontal, 12)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

        case .processing:
            Capsule(style: .continuous)
                .fill(.black)
                .frame(width: 94, height: 28)
                .overlay(
                    HStack(spacing: 8) {
                        Text("········")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.72))
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white.opacity(0.9))
                            .scaleEffect(0.8)
                    }
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private func handleTap() {
        guard !isDragging else {
            return
        }
        guard !state.isProcessing else {
            return
        }
        state.toggleRecording()
    }

    private var overlayDragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let distance = hypot(value.translation.width, value.translation.height)
                if distance > 1.5 {
                    isDragging = true
                    onDragChanged(value.translation)
                }
            }
            .onEnded { _ in
                if isDragging {
                    onDragEnded()
                }
                isDragging = false
            }
    }
}

private struct AudioWaveformView: View {
    let level: Float
    @State private var levelHistory: [CGFloat] = Array(repeating: 0, count: 11)

    private let barProfile: [CGFloat] = [0.28, 0.42, 0.58, 0.74, 0.9, 1.0, 0.9, 0.74, 0.58, 0.42, 0.28]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0 ..< barProfile.count, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(.white)
                    .frame(width: 2, height: barHeight(index: index))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            levelHistory = Array(repeating: normalizedLevel, count: barProfile.count)
        }
        .onChange(of: level) { _, newLevel in
            push(level: max(0, min(1, CGFloat(newLevel))))
        }
    }

    private var normalizedLevel: CGFloat {
        max(0, min(1, CGFloat(level)))
    }

    private func push(level: CGFloat) {
        var next = levelHistory
        next.append(level)
        while next.count > barProfile.count {
            next.removeFirst()
        }
        withAnimation(.easeOut(duration: 0.08)) {
            levelHistory = next
        }
    }

    private func barHeight(index: Int) -> CGFloat {
        let activity = levelHistory[index]
        if activity <= 0.002 {
            return 5
        }

        let boosted = pow(activity, 0.62)
        let profile = barProfile[index]
        return 4 + (boosted * (7 + (profile * 11)))
    }
}

private struct OverlayRootSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct OverlayPillFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
