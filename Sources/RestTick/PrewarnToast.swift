import AppKit
import SwiftUI

/// 到期前的非侵入预告：右上角浮层，不抢焦点、不拦截鼠标，几秒后自动消失。
@MainActor
final class PrewarnToastController {
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    func show(seconds: Int) {
        dismiss()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let size = NSSize(width: 300, height: 88)
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.maxX - size.width - 20,
            y: visibleFrame.maxY - size.height - 10
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PrewarnToastView(seconds: seconds))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 9, execute: work)
    }

    func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    func dismissImmediately() {
        dismissWork?.cancel()
        dismissWork = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

struct PrewarnToastView: View {
    let seconds: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.white.opacity(0.14))
                Image(systemName: "leaf.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(seconds) 秒后开始休息")
                    .font(.system(size: 13.5, weight: .semibold))
                Text("保存一下手头的事，准备起身活动")
                    .font(.system(size: 11.5))
                    .opacity(0.72)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.74))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(4)
    }
}
