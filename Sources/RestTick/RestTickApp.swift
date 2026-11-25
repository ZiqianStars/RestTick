import AppKit
import CoreServices
import SwiftUI

@main
struct RestTickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = RestTickEngine.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: engine)
        } label: {
            MenuBarLabel(engine: engine)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 注册 resttick:// URL 处理，这样已运行实例也能被外部触发。
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Log.app.notice("RestTick 启动")
        RestTickEngine.shared.start()

        // 冷启动时也可直接用命令行参数触发一次休息遮罩。
        if CommandLine.arguments.contains("--break-now") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                RestTickEngine.shared.startBreakNow()
            }
        }
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value) else { return }
        handleExternalURL(url)
    }

    /// 已运行实例的统一外部入口：open "resttick://break"
    private func handleExternalURL(_ url: URL) {
        guard url.scheme?.lowercased() == "resttick" else { return }
        switch (url.host ?? "").lowercased() {
        case "break", "break-now":
            Log.app.notice("外部请求触发休息")
            RestTickEngine.shared.startBreakNow()
        default:
            break
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.notice("RestTick 退出")
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        RestTickEngine.shared.shutdown()
    }
}
