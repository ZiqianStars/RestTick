import Foundation
import ImageIO
import RestTickCore

// 轻量测试运行器：当前机器只有 CommandLineTools，缺少 XCTest 与可用的 Swift Testing 宏插件，
// 因此用独立可执行 target 做断言，`scripts/test.sh` 运行它并在失败时返回非零退出码。

var failures = 0
var checks = 0

func expect(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition {
        failures += 1
        print("  FAIL  \(message)")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    expect(actual == expected, "\(message)（实际 \(actual)，期望 \(expected)）")
}

// MARK: - 空闲判定

expect(!RestTickRules.isIdle(
    systemIdle: false, mediaActive: false, screenLocked: false, screensaverActive: false
), "活跃时不应暂停")
expect(RestTickRules.isIdle(
    systemIdle: true, mediaActive: false, screenLocked: false, screensaverActive: false
), "键鼠空闲且无媒体播放时应暂停")
expect(!RestTickRules.isIdle(
    systemIdle: true, mediaActive: true, screenLocked: false, screensaverActive: false
), "播放媒体时空闲不应暂停")
expect(RestTickRules.isIdle(
    systemIdle: false, mediaActive: true, screenLocked: true, screensaverActive: false
), "锁屏时应暂停，即使正在播放媒体")
expect(RestTickRules.isIdle(
    systemIdle: true, mediaActive: true, screenLocked: false, screensaverActive: true
), "屏保时应暂停")

// MARK: - 累计时长

expectEqual(RestTickRules.accumulate(10, awakeDelta: 1, focusSeconds: 100), 11, "正常累加")
expectEqual(RestTickRules.accumulate(10, awakeDelta: 120, focusSeconds: 100), 15, "单次增量封顶 5 秒")
expectEqual(RestTickRules.accumulate(99, awakeDelta: 5, focusSeconds: 100), 100, "不超过专注周期")
expectEqual(RestTickRules.accumulate(10, awakeDelta: -3, focusSeconds: 100), 10, "忽略负增量")

// MARK: - 文本与进度

expectEqual(RestTickRules.clockText(seconds: 0), "00:00", "0 秒")
expectEqual(RestTickRules.clockText(seconds: 0.4), "00:01", "不足 1 秒向上取整")
expectEqual(RestTickRules.clockText(seconds: 61), "01:01", "61 秒")
expectEqual(RestTickRules.clockText(seconds: 3599), "59:59", "59 分 59 秒")
expectEqual(RestTickRules.clockText(seconds: 3600), "60:00", "60 分钟")
expectEqual(RestTickRules.clockText(seconds: -5), "00:00", "负数归零")

// 回归：剩余 0.005 秒时目标归零，不能被 0.01 阈值卡在 00:01。
expectEqual(RestTickRules.refreshedRemaining(current: 0.005, target: 0), 0, "目标归零时立即归零")
expectEqual(RestTickRules.refreshedRemaining(current: 0.005, target: -0.2), 0, "目标为负时归零")
expectEqual(RestTickRules.refreshedRemaining(current: 10, target: 9.5), 9.5, "正常刷新")
expectEqual(RestTickRules.refreshedRemaining(current: 10, target: 9.995), 10, "微小变化保持原值")

expect(abs(RestTickRules.fraction(elapsed: 30, total: 60) - 0.5) < 0.0001, "进度 0.5")
expectEqual(RestTickRules.fraction(elapsed: 120, total: 60), 1, "进度上限 1")
expectEqual(RestTickRules.fraction(elapsed: -10, total: 60), 0, "进度下限 0")
expectEqual(RestTickRules.fraction(elapsed: 10, total: 0), 0, "总时长为 0")

// MARK: - 跨天恢复时刻

func formatted(_ date: Date, _ calendar: Calendar) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
}

func parse(_ text: String, _ calendar: Calendar) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: text)
}

if var calendar = Optional(Calendar(identifier: .gregorian)),
   let shanghai = TimeZone(identifier: "Asia/Shanghai") {
    calendar.timeZone = shanghai
    if let now = parse("2026-11-25 15:30", calendar) {
        let next = RestTickRules.tomorrowStart(from: now, calendar: calendar)
        expectEqual(formatted(next, calendar), "2026-11-26 00:00", "恢复到次日零点")
    } else {
        expect(false, "无法构造测试时间")
    }

    if let losAngeles = TimeZone(identifier: "America/Los_Angeles") {
        calendar.timeZone = losAngeles
        if let now = parse("2026-03-08 12:00", calendar) {
            let next = RestTickRules.tomorrowStart(from: now, calendar: calendar)
            expectEqual(formatted(next, calendar), "2026-03-09 00:00", "夏令时切换日仍为次日零点")
        } else {
            expect(false, "无法构造夏令时测试时间")
        }
    }
}

// MARK: - 内置背景图规格

let backgroundsURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // RestTickTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // 仓库根目录
    .appendingPathComponent("Resources/Backgrounds")

do {
    let files = try FileManager.default
        .contentsOfDirectory(at: backgroundsURL, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension.lowercased() == "jpg" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    expectEqual(files.count, 5, "内置图数量应为 5 张")

    for url in files {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            expect(false, "无法读取 \(url.lastPathComponent)")
            continue
        }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        expectEqual(width, 2048, "\(url.lastPathComponent) 宽度")
        expectEqual(height, 1280, "\(url.lastPathComponent) 高度")
    }
} catch {
    expect(false, "扫描内置图目录失败：\(error.localizedDescription)")
}

// MARK: - 结果

if failures == 0 {
    print("全部通过：\(checks) 项检查")
    exit(0)
} else {
    print("失败 \(failures) / \(checks) 项")
    exit(1)
}
