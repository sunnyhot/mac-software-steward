import SwiftUI

enum SourcePane: String, CaseIterable, Identifiable {
    case homebrew = "Homebrew"
    case appStore = "App Store"

    var id: String { rawValue }
}

struct SourcesView: View {
    @State private var selectedPane: SourcePane = .homebrew

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                sourceHeader
                sourceContent
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 4)
        }
    }

    private var sourceHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("管理来源负责执行升级；本机应用页只展示实际安装的 .app 和来源关系。")
                .foregroundStyle(.secondary)
            Spacer()
            Picker("管理来源", selection: $selectedPane) {
                ForEach(SourcePane.allCases) { pane in
                    Text(pane.rawValue).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
        }
    }

    @ViewBuilder
    private var sourceContent: some View {
        switch selectedPane {
        case .homebrew:
            BrewSourceView()
        case .appStore:
            AppStoreSourceView()
        }
    }
}

struct BrewSourceView: View {
    @EnvironmentObject private var model: StewardModel

    private var brewDiagnosis: SourceDiagnosis? {
        guard let brew = model.scan?.brew else { return nil }
        return SourceDiagnosticEngine.diagnoseBrew(
            available: brew.available,
            error: brew.error,
            hasScan: model.scan != nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let brew = model.scan?.brew {
                InfoLine(text: brew.available ? "\(brew.version) · \(brew.prefix)" : "未检测到 Homebrew")

                // 错误诊断卡片（替代裸 WarningLine）
                if let diagnosis = brewDiagnosis {
                    ErrorRecoveryCard(
                        diagnosis: diagnosis,
                        onAction: { action in
                            Task { await model.performSourceRecovery(action: action) }
                        },
                        isProcessing: model.isScanning
                    )
                }

                PackageSection(title: "Formula", packages: filteredBrew(brew.formulae))
                PackageSection(title: "Cask", packages: filteredBrew(brew.casks))
            } else {
                EmptyStateView(symbol: "shippingbox", title: "等待扫描", text: "点击扫描后会显示 Homebrew 软件。")
            }
        }
    }

    private func filteredBrew(_ packages: [BrewPackage]) -> [BrewPackage] {
        filter(packages, query: model.query) { "\($0.name) \($0.kind) \($0.installedVersion) \($0.currentVersion)" }
    }
}

struct PackageSection: View {
    @EnvironmentObject private var model: StewardModel
    var title: String
    var packages: [BrewPackage]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(packages) { package in
                UpdateRow(package: .brew(package))
            }
        }
    }
}

struct AppStoreSourceView: View {
    @EnvironmentObject private var model: StewardModel

    var apps: [MasApp] {
        filter(model.scan?.mas.apps ?? [], query: model.query) {
            "\($0.name) \($0.appId) \($0.installedVersion) \($0.currentVersion)"
        }
    }

    private var masDiagnosis: SourceDiagnosis? {
        guard let mas = model.scan?.mas else { return nil }
        return SourceDiagnosticEngine.diagnoseMas(
            available: mas.available,
            error: mas.error,
            canInstallMas: model.canInstallMasCLI
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let mas = model.scan?.mas {
                HStack(spacing: 12) {
                    InfoLine(text: mas.available ? "通过 mas CLI 扫描与升级" : "未检测到 mas CLI")
                    Spacer()
                    if !mas.available && model.canInstallMasCLI {
                        Button {
                            Task { await model.installMasCLI() }
                        } label: {
                            Label("安装 mas CLI", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.hasRunningJob)
                    }
                }

                // 错误诊断卡片（替代裸 WarningLine）
                if let diagnosis = masDiagnosis {
                    ErrorRecoveryCard(
                        diagnosis: diagnosis,
                        onAction: { action in
                            Task { await model.performSourceRecovery(action: action) }
                        },
                        isProcessing: model.isScanning || model.hasRunningJob
                    )
                }

                // mas 不可用且无法自动安装时的额外提示（保留已有逻辑）
                if !mas.available && !model.canInstallMasCLI {
                    InstallToolPrompt(
                        title: "需要先安装 Homebrew",
                        text: "当前未检测到可用的 Homebrew，无法自动安装 mas CLI。",
                        symbol: "exclamationmark.lock"
                    )
                }
            }
            LazyVStack(spacing: 10) {
                ForEach(apps) { app in
                    UpdateRow(package: .mas(app))
                }
            }
        }
    }
}
