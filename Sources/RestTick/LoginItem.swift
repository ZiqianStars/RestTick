import AppKit
import ServiceManagement

/// 登录项（开机自启）管理。
/// 状态不落本地存储，始终以系统「登录项」中的实际注册状态为准。
@MainActor
final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()

    @Published private(set) var isEnabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var operationError: String?

    var errorMessage: String? {
        if SMAppService.mainApp.status == .notFound {
            return L10n.t("未找到登录项，请将 RestTick 移到「应用程序」文件夹后再试")
        }
        return operationError
    }

    private init() {
        refresh()
    }

    var status: SMAppService.Status { SMAppService.mainApp.status }

    /// 从系统读取真实状态，刷新开关。
    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
        if status == .enabled || status == .notRegistered {
            operationError = nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        operationError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.login.notice("登录项已\(enabled ? "注册" : "注销")")
        } catch {
            operationError = error.localizedDescription
            Log.login.error("登录项操作失败：\(error.localizedDescription, privacy: .public)")
        }
        refresh()

        // 系统需要用户在「登录项」里手动允许时，直接带用户过去。
        if enabled, SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
