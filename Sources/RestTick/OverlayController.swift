import AppKit
import SwiftUI

/// 全屏休息遮罩：每块显示器一个窗口，淡入淡出，不锁定系统、不接管电源。
@MainActor
final class OverlayController {
    private var windows: [NSWindow] = []
    private var visible = false
    private weak var engine: RestTickEngine?
    private let rotation = OverlayRotationModel()
    private var screenObserver: NSObjectProtocol?

    func show(engine: RestTickEngine) {
        self.engine = engine
        guard !visible else { return }
        visible = true
        Log.overlay.notice("显示休息遮罩：\(NSScreen.screens.count) 块屏幕，图库 \(WallpaperStore.shared.count) 张")
        rotation.start(count: WallpaperStore.shared.count)
        buildWindows(fadeIn: true)

        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.rebuild() }
            }
        }
    }

    /// 图库后台扫描完成（或图片有变化）后，让轮换模型使用最新清单。
    func wallpapersDidUpdate() {
        guard visible else { return }
        rotation.update(count: WallpaperStore.shared.count)
    }

    private func rebuild() {
        guard visible else { return }
        Log.overlay.notice("屏幕参数变化，重建遮罩窗口")
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        buildWindows(fadeIn: false)
    }

    private func buildWindows(fadeIn: Bool) {
        guard let engine else { return }
        for screen in NSScreen.screens {
            let view = BreakOverlayView(engine: engine, rotation: rotation)
            let window = OverlayWindow(screen: screen)
            window.contentView = FirstMouseHostingView(rootView: view)
            window.alphaValue = fadeIn ? 0 : 1
            window.orderFrontRegardless()
            windows.append(window)
        }
        guard fadeIn, !windows.isEmpty else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.7
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for window in self.windows { window.animator().alphaValue = 1 }
        }
    }

    func dismiss() {
        guard visible else { return }
        visible = false
        Log.overlay.notice("关闭休息遮罩")
        rotation.stop()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        let closing = windows
        windows.removeAll()
        guard !closing.isEmpty else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for window in closing { window.animator().alphaValue = 0 }
        } completionHandler: {
            for window in closing { window.orderOut(nil) }
        }
    }

    func dismissImmediately() {
        rotation.stop()
        visible = false
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
    }
}

/// 遮罩间共享的图片轮换节奏，保证多屏同步。
/// 只保留当前图片，避免把整个图库解码进内存；每次休息从上一张的下一张开始，保证长期轮换完整。
/// 图片加载是异步的，解码在后台队列完成；若加载期间又切到下一张，旧结果会被丢弃。
@MainActor
final class OverlayRotationModel: ObservableObject {
    @Published private(set) var index = 0
    @Published private(set) var currentImage: NSImage?
    private var timer: Timer?
    private var count = 0
    private var nextStart = 0
    private var loadToken = 0

    func start(count newCount: Int) {
        stop()
        count = newCount
        guard newCount > 0 else {
            index = 0
            currentImage = nil
            return
        }
        let start = nextStart % newCount
        nextStart = (start + 1) % newCount
        index = start
        loadCurrent()
        scheduleTimer()
    }

    /// 图库清单变化时更新。首次扫描完成（此前数量为 0）时也从这里开始轮换。
    func update(count newCount: Int) {
        guard newCount != count else { return }
        count = newCount
        guard newCount > 0 else {
            loadToken += 1
            timer?.invalidate()
            timer = nil
            index = 0
            currentImage = nil
            return
        }
        if currentImage == nil {
            let start = nextStart % newCount
            nextStart = (start + 1) % newCount
            index = start
            loadCurrent()
        } else if index >= newCount {
            index %= newCount
            loadCurrent()
        }
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        loadToken += 1
        count = 0
    }

    private func scheduleTimer() {
        guard count > 1 else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 18, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func advance() {
        guard count > 0 else { return }
        index = (index + 1) % count
        loadCurrent()
    }

    private func loadCurrent() {
        loadToken += 1
        let token = loadToken
        let requested = index
        WallpaperStore.shared.loadImage(at: requested) { [weak self] image in
            guard let self, self.loadToken == token, self.count > 0 else { return }
            self.currentImage = image
            self.prefetchNext()
        }
    }

    /// 提前解码下一张，切换时通常直接命中缓存，避免淡入时还是旧图。
    private func prefetchNext() {
        guard count > 1 else { return }
        WallpaperStore.shared.loadImage(at: (index + 1) % count) { _ in }
    }
}

/// 窗口在后台弹出时，第一次点击也要落到 SwiftUI 控件/长按手势上，
/// 而不是被系统用来激活窗口（否则需要点两次）。
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 使用非激活面板：点击遮罩不会切换前台 App，第一次点击也能直接落到控件/长按手势上。
final class OverlayWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)
        isOpaque = true
        backgroundColor = .black
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        alphaValue = 0
    }

    // 允许鼠标交互（长按跳过），但不主动抢焦点。
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
