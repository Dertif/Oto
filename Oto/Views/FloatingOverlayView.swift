import SwiftUI

struct FloatingOverlayView: View {
    @ObservedObject var state: AppState
    var onSizeChange: (CGSize) -> Void
    var onDragChanged: (CGSize) -> Void
    var onDragEnded: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 8) {
            if shouldShowHoverTip {
                hoverTip
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button(action: handleTap) {
                overlayPill
            }
            .buttonStyle(.plain)
            .disabled(state.isProcessing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: OverlaySizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(OverlaySizePreferenceKey.self, perform: onSizeChange)
        .onHover { hovering in
            guard state.visualState == .idle else {
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    onDragChanged(value.translation)
                }
                .onEnded { _ in
                    onDragEnded()
                }
        )
    }

    private var shouldShowHoverTip: Bool {
        state.visualState == .idle && isHovering
    }

    private var hoverTip: some View {
        Text("Click or hold fn to start dictating")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(.black)
            )
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
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
                    .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
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
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)

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
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
    }

    private func handleTap() {
        guard !state.isProcessing else {
            return
        }
        state.toggleRecording()
    }
}

private struct AudioWaveformView: View {
    let level: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 7.0
            HStack(spacing: 2) {
                ForEach(0 ..< 11, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(.white)
                        .frame(
                            width: 2,
                            height: barHeight(index: index, phase: phase)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func barHeight(index: Int, phase: TimeInterval) -> CGFloat {
        let normalizedLevel = max(0.06, min(1, CGFloat(level)))
        let modulation = abs(sin(phase + (Double(index) * 0.52)))
        let shaped = (0.2 + (0.8 * modulation)) * normalizedLevel
        return 4 + (shaped * 12)
    }
}

private struct OverlaySizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
