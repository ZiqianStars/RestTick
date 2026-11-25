import AppKit
import SwiftUI

struct BreakOverlayView: View {
    @ObservedObject var engine: RestTickEngine
    @ObservedObject var rotation: OverlayRotationModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let image = rotation.currentImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .id(rotation.index)
                        .transition(.opacity)
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.16, blue: 0.20),
                                 Color(red: 0.20, green: 0.26, blue: 0.24)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                LinearGradient(
                    colors: [.black.opacity(0.55), .black.opacity(0.15), .black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 0) {
                    Spacer(minLength: 40)

                    Text(L10n.t("休息一下"))
                        .font(.system(size: 26, weight: .regular, design: .rounded))
                        .tracking(6)
                        .opacity(0.9)

                    Spacer().frame(height: 18)

                    Text(engine.clockText)
                        .font(.system(size: 110, weight: .ultraLight, design: .rounded))
                        .monospacedDigit()
                        .opacity(0.97)

                    Spacer().frame(height: 10)

                    Text(L10n.t("看看远处，活动肩颈，让眼睛放松"))
                        .font(.system(size: 16, weight: .regular))
                        .opacity(0.78)

                    Spacer()

                    HoldToSkipButton {
                        engine.skipBreak()
                    }

                    Spacer().frame(height: 24)

                    HStack(spacing: 26) {
                        Button(L10n.t("暂停 30 分钟")) { engine.pause(minutes: 30) }
                        Button(L10n.t("今天不再提醒")) { engine.pauseToday() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5))
                    .opacity(0.7)

                    Spacer().frame(height: 26)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 2)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("RestTick")
                            .font(.system(size: 11, weight: .medium))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .padding(20)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.6), value: rotation.index)
        .environment(\.colorScheme, .dark)
    }
}

/// 长按 3 秒才能跳过休息，避免手滑，也不做系统级拦截。
struct HoldToSkipButton: View {
    let holdSeconds: Double = 3
    let action: () -> Void

    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            Capsule()
                .fill(.white.opacity(0.10))

            Capsule()
                .trim(from: 0, to: progress)
                .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .padding(1)

            Text(L10n.t(progress > 0.02 ? "继续按住…" : "按住 3 秒跳过本次休息"))
                .font(.system(size: 13, weight: .medium))
                .opacity(progress > 0.02 ? 0.95 : 0.7)
        }
        .frame(width: 240, height: 42)
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: holdSeconds, maximumDistance: 80, pressing: { pressing in
            withAnimation(.linear(duration: pressing ? holdSeconds : 0.25)) {
                progress = pressing ? 1 : 0
            }
        }, perform: {
            progress = 0
            action()
        })
    }
}
