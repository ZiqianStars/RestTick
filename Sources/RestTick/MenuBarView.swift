import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var engine: RestTickEngine

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: engine.menuBarSymbol)
            Text(engine.menuBarText)
                .monospacedDigit()
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var engine: RestTickEngine
    @ObservedObject private var loginItem = LoginItemManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            countdown
            settings
            actions
            footer
        }
        .padding(16)
        .frame(width: 306)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .center) {
            Text("RestTick")
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.2)
            Spacer()
            Text(engine.statusBadge)
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                .foregroundStyle(Color.accentColor)
        }
        .frame(height: 22)
    }

    // MARK: - 倒计时

    private var countdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(engine.clockText)
                .font(.system(size: 41, weight: .light))
                .monospacedDigit()
                .tracking(-1)
                .lineLimit(1)

            ProgressView(value: engine.progress)
                .progressViewStyle(.linear)
                .tint(.accentColor)

            Text(engine.statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 设置

    private var settings: some View {
        VStack(spacing: 0) {
            settingRow(
                title: L10n.t("定时时长"),
                binding: $engine.focusMinutes,
                range: 5...180,
                step: 5,
                unit: L10n.t("分钟")
            )
            Divider().opacity(0.6)
            settingRow(
                title: L10n.t("休息时长"),
                binding: $engine.breakMinutes,
                range: 1...30,
                step: 1,
                unit: L10n.t("分钟")
            )
            Divider().opacity(0.6)
            loginRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
        )
    }

    private func settingRow(
        title: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
            Spacer()
            HStack(spacing: 5) {
                compactStepper(binding, range: range, step: step, label: title)
                Text(unit)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 30)
    }

    private func compactStepper(
        _ binding: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        label: String
    ) -> some View {
        HStack(spacing: 0) {
            stepperButton("minus", label: L10n.t("减少%@", label)) {
                adjust(binding, by: -step, in: range)
            }
            Text("\(Int(binding.wrappedValue))")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .frame(width: 26)
            stepperButton("plus", label: L10n.t("增加%@", label)) {
                adjust(binding, by: step, in: range)
            }
        }
        .frame(height: 20)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.13), lineWidth: 0.5)
        )
    }

    private func stepperButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .bold))
                .frame(width: 18, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
    }

    private func adjust(_ binding: Binding<Double>, by delta: Double, in range: ClosedRange<Double>) {
        binding.wrappedValue = min(range.upperBound, max(range.lowerBound, binding.wrappedValue + delta))
    }

    private var loginRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(L10n.t("开机自动启动"))
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .frame(height: 30)

            if let message = loginItem.errorMessage {
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if loginItem.needsApproval {
                HStack(spacing: 4) {
                    Text(L10n.t("需在系统设置的「登录项」中允许"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                    Button(L10n.t("去设置")) { loginItem.openSystemSettings() }
                        .buttonStyle(.link)
                        .font(.system(size: 10.5))
                }
            }
        }
        .padding(.vertical, 1)
    }

    // MARK: - 操作

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                engine.startBreakNow()
            } label: {
                Label(L10n.t("现在休息"), systemImage: "cup.and.saucer.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(engine.isResting)

            if engine.isPaused {
                Button {
                    engine.resumeNow()
                } label: {
                    Text(L10n.t("继续计时")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                HStack(spacing: 8) {
                    Button {
                        engine.pause(minutes: 30)
                    } label: {
                        Text(L10n.t("暂停 30 分钟")).frame(maxWidth: .infinity)
                    }
                    Button {
                        engine.pauseToday()
                    } label: {
                        Text(L10n.t("今天不再提醒")).frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                NSWorkspace.shared.open(WallpaperStore.shared.folderURL)
            } label: {
                Label(L10n.t("打开图库"), systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n.t("把喜欢的图片放进打开的文件夹，下次休息自动使用"))
        }
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let note = engine.noteText {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(L10n.t("重新计时")) { engine.restart() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                Spacer()
                Button(L10n.t("退出 RestTick")) { NSApp.terminate(nil) }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("空闲 90 秒自动暂停计时（播放媒体时除外）"))
                Text(L10n.t("到点弹出休息遮罩 · 已完成 %d 次休息", engine.completedBreaks))
            }
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
