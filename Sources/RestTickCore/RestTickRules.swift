import Foundation

/// 计时规则的纯函数实现：与界面、系统 API 解耦，便于单元测试与复用。
public enum RestTickRules {
    /// 是否暂停累计：锁屏、屏保一定暂停；键鼠空闲时，若正在播放媒体则视为仍在使用。
    public static func isIdle(
        systemIdle: Bool,
        mediaActive: Bool,
        screenLocked: Bool,
        screensaverActive: Bool
    ) -> Bool {
        (systemIdle && !mediaActive) || screenLocked || screensaverActive
    }

    /// 累加清醒时长：忽略负增量，单次增量封顶，总量不超过一个专注周期。
    public static func accumulate(
        _ accumulated: TimeInterval,
        awakeDelta: TimeInterval,
        focusSeconds: TimeInterval,
        deltaCap: TimeInterval = 5
    ) -> TimeInterval {
        min(max(0, accumulated) + min(max(0, awakeDelta), deltaCap), max(0, focusSeconds))
    }

    /// 倒计时文本 mm:ss，向上取整，避免剩余不足 1 秒时提前显示 00:00。
    public static func clockText(seconds: TimeInterval) -> String {
        let total = Int(ceil(max(0, seconds)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// 刷新倒计时显示值：目标归零时立即归零，避免 0.01 秒的刷新阈值
    /// 把剩余时间卡在 0.005 秒，界面一直显示 00:01 且结束条件永远不成立。
    public static func refreshedRemaining(current: TimeInterval, target: TimeInterval) -> TimeInterval {
        let clamped = max(0, target)
        guard clamped > 0 else { return 0 }
        return abs(current - clamped) > 0.01 ? clamped : current
    }

    /// 暂停时的累计值：休息中暂停要清零，恢复后重新走完整专注周期，
    /// 避免恢复瞬间因为累计已满而立刻再次弹出休息遮罩。
    public static func accumulatedAfterPausing(
        isResting: Bool,
        accumulated: TimeInterval
    ) -> TimeInterval {
        isResting ? 0 : accumulated
    }

    /// 暂停是否已经到期；到点即恢复，避免因为取整或定时器抖动多暂停一轮。
    public static func pauseHasExpired(now: Date, until: Date) -> Bool {
        now >= until
    }

    /// 恢复计时时的累计值：已达到一个完整周期就清零，否则保留原进度。
    public static func accumulatedAfterResuming(
        _ accumulated: TimeInterval,
        focusSeconds: TimeInterval
    ) -> TimeInterval {
        accumulated >= focusSeconds ? 0 : accumulated
    }

    /// 0...1 的进度比例；总时长为 0 时返回 0。
    public static func fraction(elapsed: TimeInterval, total: TimeInterval) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, elapsed / total))
    }

    /// “今天不再提醒”的恢复时刻：次日零点。
    /// 用“当天起点 + 1 天”计算，避免夏令时切换日得到错误的时间点。
    public static func tomorrowStart(from now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(86_400)
    }
}
