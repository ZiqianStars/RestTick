import AppKit
import RestTickCore
import SwiftUI

enum RestPhase: Equatable {
    case counting
    case resting(end: Date)
    case paused(until: Date)
}

/// 计时与调度中枢。
/// 计时以“累计清醒活跃时间”为准：键鼠空闲超阈值、锁屏、屏保时都不计时；
/// 但有媒体播放（其他进程持有防熄屏断言）时视为仍在使用电脑，空闲也不暂停计时。
/// 休眠/唤醒后按单调时钟重新校准，避免把睡眠时间或一次长跳变算进使用时长。
@MainActor
final class RestTickEngine: ObservableObject {
    static let shared = RestTickEngine()

    private enum Keys {
        static let focus = "focusMinutes"
        static let breakTime = "breakMinutes"
    }

    /// 计时器的运行模式：暂停阶段只在恢复时刻唤醒一次。
    private enum TimerMode: Equatable {
        case running
        case paused(until: Date)
    }

    private static let lockNote = "屏幕已锁定，计时暂停"
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    @Published var focusMinutes: Double = 45 {
        didSet {
            UserDefaults.standard.set(focusMinutes, forKey: Keys.focus)
            guard case .counting = phase else { return }
            recomputeRemaining()
            if remaining > prewarnLead { prewarned = false }
        }
    }

    @Published var breakMinutes: Double = 5 {
        didSet { UserDefaults.standard.set(breakMinutes, forKey: Keys.breakTime) }
    }

    @Published private(set) var phase: RestPhase = .counting
    @Published private(set) var remaining: TimeInterval = 45 * 60
    @Published private(set) var isIdle = false
    @Published private(set) var mediaActive = false
    @Published private(set) var note: String?
    @Published private(set) var completedBreaks = 0
    @Published private(set) var skippedBreaks = 0

    let prewarnLead: TimeInterval = 45
    let idleThreshold: TimeInterval = 90

    private var accumulated: TimeInterval = 0
    private var prewarned = false
    private var pausedForToday = false
    private var timer: Timer?
    private var scheduledMode: TimerMode?
    private var activityToken: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    private var screensaverActive = false
    private var screenLocked = false
    private var lastSessionCheck = 0.0
    private var lastMediaCheck = 0.0
    private var started = false
    private let overlay = OverlayController()
    private let toast = PrewarnToastController()

    private var lastAwake = 0.0
    private var lastContinuous = 0.0
    private var wasIdle = false

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.focus) != nil {
            focusMinutes = defaults.double(forKey: Keys.focus)
        }
        if defaults.object(forKey: Keys.breakTime) != nil {
            breakMinutes = defaults.double(forKey: Keys.breakTime)
        }
        remaining = max(60, focusMinutes * 60)
    }

    // MARK: - 派生状态

    var focusSeconds: TimeInterval { max(60, focusMinutes * 60) }
    var breakSeconds: TimeInterval { max(10, breakMinutes * 60) }
    var isResting: Bool { if case .resting = phase { return true }; return false }
    var isPaused: Bool { if case .paused = phase { return true }; return false }

    var clockText: String {
        if case .paused = phase { return "--:--" }
        return RestTickRules.clockText(seconds: remaining)
    }

    var progress: Double {
        switch phase {
        case .resting(let end):
            let elapsed = breakSeconds - max(0, end.timeIntervalSinceNow)
            return RestTickRules.fraction(elapsed: elapsed, total: breakSeconds)
        case .counting, .paused:
            return RestTickRules.fraction(elapsed: accumulated, total: focusSeconds)
        }
    }

    var statusText: String {
        switch phase {
        case .counting:
            if isIdle { return "已离开电脑，计时自动暂停" }
            if remaining <= prewarnLead && remaining > 0 { return "即将开始休息，请保存手头工作" }
            if mediaActive { return "检测到媒体播放，继续计时" }
            return "距离休息还有 \(clockText)"
        case .resting:
            return "休息中，看看远处放松一下"
        case .paused(let until):
            if pausedForToday { return "今天不再提醒" }
            return "已暂停，将于 \(Self.timeFormatter.string(from: until)) 恢复"
        }
    }

    var statusBadge: String {
        switch phase {
        case .resting: return "休息中"
        case .paused: return "已暂停"
        case .counting:
            if isIdle { return "空闲" }
            return "计时中"
        }
    }

    var menuBarText: String {
        switch phase {
        case .resting:
            return clockText
        case .paused:
            return "暂停"
        case .counting:
            if isIdle { return "空闲" }
            return "\(Int(ceil(remaining / 60)))m"
        }
    }

    var menuBarSymbol: String {
        switch phase {
        case .resting: return "cup.and.saucer.fill"
        case .paused: return "pause.circle"
        case .counting:
            if isIdle { return "leaf" }
            return "timer"
        }
    }

    // MARK: - 生命周期

    func start() {
        guard !started else { return }
        started = true
        Log.engine.notice("开始计时：专注 \(Int(self.focusMinutes)) 分钟，休息 \(Int(self.breakMinutes)) 分钟")

        // 阻止 App Nap 合并计时器，同时允许系统正常休眠。
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "RestTick 连续使用计时"
        )

        lastAwake = MonotonicClock.awakeNow()
        lastContinuous = MonotonicClock.continuousNow()

        registerSystemObservers()
        configureTimer()
        tick()

        // 稍后在空闲时预生成/解码第一张护眼图，避免第一次休息时临时处理。
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            WallpaperStore.shared.prewarm()
        }
    }

    func shutdown() {
        Log.engine.notice("停止计时")
        timer?.invalidate()
        timer = nil
        scheduledMode = nil
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let distributedCenter = DistributedNotificationCenter.default()
        for observer in observers {
            workspaceCenter.removeObserver(observer)
            distributedCenter.removeObserver(observer)
        }
        observers.removeAll()
        overlay.dismissImmediately()
        toast.dismissImmediately()
    }

    private func registerSystemObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let distributedCenter = DistributedNotificationCenter.default()

        let wakeNames: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ]
        for name in wakeNames {
            let observer = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleWake() }
            }
            observers.append(observer)
        }

        let lockObserver = distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.note = Self.lockNote }
        }
        observers.append(lockObserver)

        let unlockObserver = distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.note == Self.lockNote { self.note = nil }
                self.handleWake()
            }
        }
        observers.append(unlockObserver)

        let screensaverStart = distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screensaver.didstart"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screensaverActive = true }
        }
        observers.append(screensaverStart)

        let screensaverStop = distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screensaver.didstop"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screensaverActive = false }
        }
        observers.append(screensaverStop)
    }

    // MARK: - 主循环

    private func tick() {
        let nowAwake = MonotonicClock.awakeNow()
        let nowContinuous = MonotonicClock.continuousNow()
        let awakeDelta = max(0, nowAwake - lastAwake)
        let continuousDelta = max(0, nowContinuous - lastContinuous)
        let slept = continuousDelta - awakeDelta > 1.5

        lastAwake = nowAwake
        lastContinuous = nowContinuous

        if slept { handleWakeGap() }

        switch phase {
        case .counting:
            refreshSystemState(now: nowAwake)
            let systemIdle = ActivityMonitor.idleSeconds >= idleThreshold
            let idle = RestTickRules.isIdle(
                systemIdle: systemIdle,
                mediaActive: mediaActive,
                screenLocked: screenLocked,
                screensaverActive: screensaverActive
            )
            setIdle(idle)
            if idle {
                wasIdle = true
            } else if wasIdle {
                // 用户回到电脑前：若此时已进入预告窗口，重新给一次预告。
                wasIdle = false
                if remaining > 0, remaining <= prewarnLead { prewarned = false }
            }
            if !idle {
                // 上限截断，避免计时器被系统合并造成一次巨大跳变。
                accumulated = RestTickRules.accumulate(
                    accumulated,
                    awakeDelta: awakeDelta,
                    focusSeconds: focusSeconds
                )
            }
            updateRemaining(max(0, focusSeconds - accumulated))
            if remaining <= prewarnLead { prewarnIfNeeded() }
            if remaining <= 0 { beginBreak() }

        case .resting(let end):
            setIdle(false)
            updateRemaining(max(0, end.timeIntervalSinceNow))
            if remaining <= 0 { finishBreak(skipped: false) }

        case .paused(let until):
            setIdle(false)
            updateRemaining(max(0, until.timeIntervalSinceNow))
            if Date() >= until { resumeFromPause() }
        }
    }

    /// 锁屏与媒体断言不需要每秒查询：锁屏每 2 秒、媒体每 5 秒检查一次，其余 tick 复用结果。
    private func refreshSystemState(now: Double) {
        if now - lastSessionCheck >= 2 {
            lastSessionCheck = now
            screenLocked = ActivityMonitor.screenIsLocked
        }
        if now - lastMediaCheck >= 5 {
            lastMediaCheck = now
            let active = ActivityMonitor.hasDisplaySleepAssertion()
            if mediaActive != active { mediaActive = active }
        }
    }

    private func setIdle(_ value: Bool) {
        if isIdle != value { isIdle = value }
    }

    private func updateRemaining(_ value: TimeInterval) {
        if abs(remaining - value) > 0.01 { remaining = value }
    }

    private func handleWake() {
        lastAwake = MonotonicClock.awakeNow()
        lastContinuous = MonotonicClock.continuousNow()
        handleWakeGap()
    }

    private func handleWakeGap() {
        if case .resting(let end) = phase, Date() >= end {
            finishBreak(skipped: false)
        }
        if case .paused(let until) = phase, Date() >= until {
            resumeFromPause()
        }
        // 唤醒后允许重新提示一次，避免睡醒后错过预告。
        if case .counting = phase, remaining > 0, remaining <= prewarnLead {
            prewarned = false
        }
    }

    private func prewarnIfNeeded() {
        guard !prewarned, remaining > 0 else { return }
        prewarned = true
        guard !ActivityMonitor.screenIsLocked, !screensaverActive else { return }
        toast.show(seconds: Int(ceil(remaining)))
    }

    // MARK: - 计时器

    /// 按状态切换计时器频率：计时/休息每秒一次；暂停时只在恢复时刻唤醒一次。
    private func configureTimer() {
        let mode: TimerMode
        switch phase {
        case .counting, .resting: mode = .running
        case .paused(let until): mode = .paused(until: until)
        }
        guard mode != scheduledMode || timer?.isValid != true else { return }

        timer?.invalidate()
        timer = nil
        scheduledMode = mode

        let timer: Timer
        switch mode {
        case .running:
            timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        case .paused(let until):
            // 留出一点余量，确保醒来时已经越过恢复时刻。
            let fireDate = max(until, Date().addingTimeInterval(0.05))
            timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - 休息流程

    private func beginBreak() {
        Log.engine.notice("开始休息：\(Int(self.breakSeconds)) 秒")
        note = nil
        accumulated = focusSeconds
        phase = .resting(end: Date().addingTimeInterval(breakSeconds))
        remaining = breakSeconds
        isIdle = false
        toast.dismiss()
        configureTimer()
        overlay.show(engine: self)
        // 图库扫描在后台完成，遮罩先弹出；扫描结束后再让轮换使用最新图片。
        WallpaperStore.shared.reload { [weak self] in
            self?.overlay.wallpapersDidUpdate()
        }
    }

    private func finishBreak(skipped: Bool) {
        Log.engine.notice("休息结束：skipped=\(skipped)")
        overlay.dismiss()
        if skipped {
            skippedBreaks += 1
            note = "本次休息已跳过"
        } else {
            completedBreaks += 1
            note = "休息完成，继续加油"
        }
        accumulated = 0
        prewarned = false
        pausedForToday = false
        phase = .counting
        remaining = focusSeconds
        lastAwake = MonotonicClock.awakeNow()
        lastContinuous = MonotonicClock.continuousNow()
        configureTimer()
    }

    // MARK: - 用户操作

    func startBreakNow() {
        beginBreak()
    }

    func skipBreak() {
        guard case .resting = phase else { return }
        finishBreak(skipped: true)
    }

    func pause(minutes: Int) {
        Log.engine.notice("暂停 \(minutes) 分钟")
        overlay.dismiss()
        toast.dismiss()
        // 休息中暂停：恢复后应重新开始一个完整的计时周期，而不是立刻再弹遮罩。
        if case .resting = phase { accumulated = 0 }
        pausedForToday = false
        let until = Date().addingTimeInterval(Double(minutes) * 60)
        phase = .paused(until: until)
        remaining = max(0, until.timeIntervalSinceNow)
        prewarned = false
        note = "已暂停 \(minutes) 分钟"
        configureTimer()
    }

    func pauseToday() {
        Log.engine.notice("今天不再提醒")
        overlay.dismiss()
        toast.dismiss()
        if case .resting = phase { accumulated = 0 }
        pausedForToday = true
        let tomorrow = RestTickRules.tomorrowStart(from: Date())
        phase = .paused(until: tomorrow)
        remaining = max(0, tomorrow.timeIntervalSinceNow)
        prewarned = false
        note = "今天不再提醒"
        configureTimer()
    }

    func resumeNow() {
        guard isPaused else { return }
        resumeFromPause()
    }

    private func resumeFromPause() {
        Log.engine.notice("恢复计时")
        if accumulated >= focusSeconds { accumulated = 0 }
        pausedForToday = false
        phase = .counting
        prewarned = false
        note = "已恢复计时"
        isIdle = false
        remaining = max(0, focusSeconds - accumulated)
        // 暂停期间计时器是停的，恢复时重置基准，避免把暂停时长算进使用时间。
        lastAwake = MonotonicClock.awakeNow()
        lastContinuous = MonotonicClock.continuousNow()
        configureTimer()
    }

    func restart() {
        Log.engine.notice("重新计时")
        overlay.dismiss()
        toast.dismiss()
        accumulated = 0
        prewarned = false
        pausedForToday = false
        phase = .counting
        remaining = focusSeconds
        note = nil
        isIdle = false
        lastAwake = MonotonicClock.awakeNow()
        lastContinuous = MonotonicClock.continuousNow()
        configureTimer()
    }

    private func recomputeRemaining() {
        remaining = max(0, focusSeconds - accumulated)
    }
}
