import CoreGraphics
import Darwin
import Foundation
import IOKit.pwr_mgt
import OSLog

/// 统一日志入口。排查问题时执行：
/// `log stream --predicate 'subsystem == "com.resttick.app"' --level debug`
enum Log {
    private static let subsystem = "com.resttick.app"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
    static let wallpaper = Logger(subsystem: subsystem, category: "wallpaper")
    static let login = Logger(subsystem: subsystem, category: "login")
}

/// 单调时钟封装。
/// - `awakeNow`: 不含系统休眠的计时（mach_absolute_time 在睡眠期间停止），用于累计“连续使用时间”。
/// - `continuousNow`: 含休眠的计时，用于识别休眠/唤醒造成的跳变并校准。
enum MonotonicClock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func seconds(_ ticks: UInt64) -> Double {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000.0
    }

    static func awakeNow() -> Double {
        seconds(mach_absolute_time())
    }

    static func continuousNow() -> Double {
        seconds(mach_continuous_time())
    }
}

/// 系统键盘/鼠标空闲检测与会话锁屏状态。
enum ActivityMonitor {
    /// 距上一次键鼠输入过去的秒数（合并会话状态）。
    static var idleSeconds: Double {
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    static var screenIsLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    /// 是否有其他进程持有“阻止显示器空闲休眠”的电源断言。
    ///
    /// 浏览器/播放器看视频、`caffeinate -d` 都会持有这类断言，可作为“正在使用电脑”的信号；
    /// 而 `PreventUserIdleSystemSleep` 在屏幕点亮时由 powerd 长期持有，不能作为判据。
    /// 自身进程的断言（计时用的 beginActivity）需要排除。
    static func hasDisplaySleepAssertion(excluding pid: pid_t = getpid()) -> Bool {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byProcess = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else {
            return false
        }

        let displayTypes: Set<String> = [
            kIOPMAssertionTypePreventUserIdleDisplaySleep as String,
            "NoDisplaySleepAssertion"
        ]
        for (owner, assertions) in byProcess {
            guard owner.int32Value != pid else { continue }
            for assertion in assertions {
                guard let type = assertion[kIOPMAssertionTypeKey as String] as? String,
                      displayTypes.contains(type) else { continue }
                let level = (assertion[kIOPMAssertionLevelKey as String] as? NSNumber)?.intValue ?? 255
                if level != 0 { return true }
            }
        }
        return false
    }
}
