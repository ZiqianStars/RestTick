import AppKit
import Foundation

enum AppLanguage: String {
    case chinese = "zh-Hans"
    case english = "en"
}

extension Notification.Name {
    static let restTickLanguageDidChange = Notification.Name("RestTickLanguageDidChange")
}

/// 跟随系统语言，并在语言变化时通知界面重新渲染，不需要重启 App。
/// 文案直接以简体中文为 key，英文缺失时回退中文，便于逐个补齐。
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published private(set) var language: AppLanguage

    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    private init() {
        language = Self.resolveLanguage()

        // 系统语言变化没有稳定的跨进程通知；低频轮询偏好作为兜底，
        // 保证用户切回 App 或停留在遮罩上时也能在几秒内生效。
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
    }

    func refresh() {
        let next = Self.resolveLanguage()
        guard next != language else { return }
        language = next
        NotificationCenter.default.post(name: .restTickLanguageDidChange, object: nil)
        Log.app.notice("界面语言已切换为 \(next.rawValue, privacy: .public)")
    }

    func string(for key: String) -> String {
        guard language == .english else { return key }
        return Self.english[key] ?? key
    }

    private static func resolveLanguage() -> AppLanguage {
        let appID = (Bundle.main.bundleIdentifier ?? "com.resttick.app") as CFString
        let code: String
        if let languages = CFPreferencesCopyAppValue("AppleLanguages" as CFString, appID) as? [String],
           let first = languages.first {
            // 支持 macOS 的按 App 语言设置，也方便测试时单独切换 RestTick。
            code = first
        } else if let languages = CFPreferencesCopyAppValue(
            "AppleLanguages" as CFString,
            kCFPreferencesAnyApplication
        ) as? [String], let first = languages.first {
            code = first
        } else {
            code = Locale.preferredLanguages.first ?? "en"
        }
        return code.lowercased().hasPrefix("zh") ? .chinese : .english
    }

    private static let english: [String: String] = [
        // 菜单面板
        "定时时长": "Focus duration",
        "休息时长": "Break duration",
        "分钟": "min",
        "减少%@": "Decrease %@",
        "增加%@": "Increase %@",
        "开机自动启动": "Launch at login",
        "需在系统设置的「登录项」中允许": "Allow in System Settings › Login Items",
        "去设置": "Open Settings",
        "现在休息": "Take a Break",
        "继续计时": "Resume",
        "暂停 30 分钟": "Pause 30 min",
        "今天不再提醒": "No reminders today",
        "打开图库": "Open Gallery",
        "把喜欢的图片放进打开的文件夹，下次休息自动使用": "Put images you like in the opened folder; they will be used on the next break.",
        "重新计时": "Restart",
        "退出 RestTick": "Quit RestTick",
        "空闲 90 秒自动暂停计时（播放媒体时除外）": "Pauses after 90 s idle (except during media playback)",
        "到点弹出休息遮罩 · 已完成 %d 次休息": "Full-screen break at zero · %d breaks completed",

        // 休息遮罩
        "休息一下": "Take a break",
        "看看远处，活动肩颈，让眼睛放松": "Look into the distance, stretch your neck and shoulders, and let your eyes relax.",
        "继续按住…": "Keep holding…",
        "按住 3 秒跳过本次休息": "Hold for 3 seconds to skip this break",

        // 到期预告
        "%d 秒后开始休息": "Break starts in %d seconds",
        "保存一下手头的事，准备起身活动": "Save what you're doing and get ready to move.",

        // 登录项
        "未找到登录项，请将 RestTick 移到「应用程序」文件夹后再试": "Login item not found. Move RestTick to the Applications folder and try again.",

        // 状态与提示
        "已离开电脑，计时自动暂停": "You're away; the timer is paused",
        "即将开始休息，请保存手头工作": "Break starting soon — save your work",
        "检测到媒体播放，继续计时": "Media playback detected; the timer continues",
        "距离休息还有 %@": "Break in %@",
        "休息中，看看远处放松一下": "On a break — look into the distance",
        "已暂停，将于 %@ 恢复": "Paused until %@",
        "休息中": "Resting",
        "已暂停": "Paused",
        "空闲": "Away",
        "计时中": "Focusing",
        "暂停": "Paused",
        "屏幕已锁定，计时暂停": "Screen locked; the timer is paused",
        "本次休息已跳过": "Break skipped",
        "休息完成，继续加油": "Break complete — nice work",
        "已暂停 %d 分钟": "Paused for %d minutes",
        "已恢复计时": "Timer resumed"
    ]
}

@MainActor
enum L10n {
    static func t(_ key: String) -> String {
        LocalizationManager.shared.string(for: key)
    }

    static func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: LocalizationManager.shared.string(for: key), arguments: args)
    }
}
