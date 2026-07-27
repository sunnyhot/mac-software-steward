import Foundation
import AppKit

// MARK: - 管理来源错误诊断数据

/// 管理来源错误诊断结果：中文原因 + 建议 + 可执行操作
struct SourceDiagnosis {
    var reason: String
    var suggestion: String
    var action: SourceRecoveryAction?
    var actionLabel: String?
    /// 可复制到终端的手动命令（可选）
    var terminalCommand: String?
    /// 终端命令说明
    var terminalHint: String?
}

/// 来源诊断卡片支持的恢复操作类型
enum SourceRecoveryAction: Hashable {
    case rescan
    case installMas
    case openURL(URL)
}

// MARK: - 诊断逻辑（纯函数，方便测试）

enum SourceDiagnosticEngine {

    /// 诊断 Homebrew 状态
    static func diagnoseBrew(available: Bool, error: String, hasScan: Bool) -> SourceDiagnosis? {
        if !available {
            return SourceDiagnosis(
                reason: "未检测到 Homebrew",
                suggestion: "Homebrew 是 macOS 的软件包管理器，升级功能依赖它。请先安装 Homebrew。",
                action: .openURL(URL(string: "https://brew.sh")!),
                actionLabel: "访问 Homebrew 官网",
                terminalCommand: "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
                terminalHint: "或在终端中运行官方安装脚本"
            )
        }
        if error.isEmpty { return nil }

        let lowercased = error.lowercased()

        if lowercased.contains("timeout") || lowercased.contains("timed out") || lowercased.contains("connection") || lowercased.contains("could not resolve") {
            return SourceDiagnosis(
                reason: "Homebrew 连接网络失败",
                suggestion: "请检查网络连接是否正常。如果使用代理，确保代理配置正确。",
                action: .rescan,
                actionLabel: "重新扫描",
                terminalCommand: "brew update",
                terminalHint: "或在终端中运行 brew update 检查网络"
            )
        }

        if lowercased.contains("permission denied") || lowercased.contains("operation not permitted") {
            return SourceDiagnosis(
                reason: "Homebrew 权限不足",
                suggestion: "Homebrew 无法访问所需的目录。请在终端中运行修复命令。",
                action: .rescan,
                actionLabel: "重新扫描",
                terminalCommand: "brew doctor",
                terminalHint: "在终端运行 brew doctor 查看详细问题"
            )
        }

        if lowercased.contains("not found") || lowercased.contains("no such file") {
            return SourceDiagnosis(
                reason: "Homebrew 组件缺失或路径损坏",
                suggestion: "部分 Homebrew 文件丢失。请尝试重新扫描，如持续失败可在终端运行 brew doctor 检查。",
                action: .rescan,
                actionLabel: "重新扫描",
                terminalCommand: nil,
                terminalHint: nil
            )
        }

        return SourceDiagnosis(
            reason: "Homebrew 扫描遇到错误",
            suggestion: "部分操作未成功完成。可以尝试重新扫描，如持续失败请在终端运行 brew doctor 检查。",
            action: .rescan,
            actionLabel: "重新扫描",
            terminalCommand: "brew doctor",
            terminalHint: "在终端运行 brew doctor 查看详细问题"
        )
    }

    /// 诊断 mas CLI 状态
    static func diagnoseMas(available: Bool, error: String, canInstallMas: Bool) -> SourceDiagnosis? {
        if !available {
            if error.contains("崩溃") {
                return SourceDiagnosis(
                    reason: "mas CLI 运行异常",
                    suggestion: "mas CLI 已安装但运行时崩溃。通常是因为未在 App Store 中登录，或当前系统版本不兼容。",
                    action: canInstallMas ? .installMas : nil,
                    actionLabel: canInstallMas ? "重新安装 mas CLI" : nil,
                    terminalCommand: "mas list",
                    terminalHint: "在终端中运行 mas list 检查是否正常"
                )
            }
            return SourceDiagnosis(
                reason: "未检测到 mas CLI",
                suggestion: canInstallMas
                    ? "mas CLI 用于管理 App Store 应用。点击下方按钮可通过 Homebrew 自动安装。"
                    : "mas CLI 用于管理 App Store 应用，但需要先安装 Homebrew 才能自动安装。",
                action: canInstallMas ? .installMas : nil,
                actionLabel: canInstallMas ? "安装 mas CLI" : nil,
                terminalCommand: canInstallMas ? nil : "brew install mas",
                terminalHint: canInstallMas ? nil : "安装 Homebrew 后可自动安装，或直接在终端运行 brew install mas"
            )
        }
        if error.isEmpty { return nil }

        let lowercased = error.lowercased()

        if lowercased.contains("崩溃") || lowercased.contains("signal") || lowercased.contains("sigsegv") || lowercased.contains("sigabrt") {
            return SourceDiagnosis(
                reason: "mas CLI 部分命令运行异常",
                suggestion: "mas CLI 在扫描过程中出现崩溃，可能需要重新登录 App Store 或更新 mas。",
                action: .rescan,
                actionLabel: "重新扫描",
                terminalCommand: "mas account",
                terminalHint: "在终端中运行 mas account 检查登录状态"
            )
        }

        if lowercased.contains("timeout") || lowercased.contains("timed out") || lowercased.contains("connection") {
            return SourceDiagnosis(
                reason: "App Store 网络连接失败",
                suggestion: "无法连接 App Store 服务器。请检查网络连接。",
                action: .rescan,
                actionLabel: "重新扫描",
                terminalCommand: nil,
                terminalHint: nil
            )
        }

        return SourceDiagnosis(
            reason: "App Store 扫描遇到错误",
            suggestion: "部分 mas 命令执行失败。可以尝试重新扫描。",
            action: .rescan,
            actionLabel: "重新扫描",
            terminalCommand: "mas list",
            terminalHint: "在终端中运行 mas list 检查是否正常"
        )
    }
}
