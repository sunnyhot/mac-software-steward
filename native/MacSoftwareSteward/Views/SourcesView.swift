import SwiftUI

enum SourcePane: String, CaseIterable, Identifiable {
    case homebrew = "Homebrew"
    case appStore = "App Store"

    var id: String { rawValue }
}

struct SourcesView: View {
    @State private var selectedPane: SourcePane = .homebrew

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("管理来源负责执行升级；本机应用页只展示实际安装的 .app 和来源关系。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("管理来源", selection: $selectedPane) {
                    ForEach(SourcePane.allCases) { pane in
                        Text(pane.rawValue).tag(pane)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            switch selectedPane {
            case .homebrew:
                BrewSourceView()
            case .appStore:
                AppStoreSourceView()
            }
        }
    }
}

struct BrewSourceView: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let brew = model.scan?.brew {
                    InfoLine(text: brew.available ? "\(brew.version) · \(brew.prefix)" : "未检测到 Homebrew")
                    if !brew.error.isEmpty {
                        WarningLine(text: brew.error)
                    }
                    PackageSection(title: "Formula", packages: filteredBrew(brew.formulae))
                    PackageSection(title: "Cask", packages: filteredBrew(brew.casks))
                } else {
                    EmptyStateView(symbol: "shippingbox", title: "等待扫描", text: "点击扫描后会显示 Homebrew 软件。")
                }
            }
            .padding(16)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let mas = model.scan?.mas {
                HStack(spacing: 12) {
                    InfoLine(text: mas.available ? "通过 mas CLI 扫描与升级" : "未检测到 mas CLI")
                    Spacer()
                    if !mas.available {
                        Button {
                            Task { await model.installMasCLI() }
                        } label: {
                            Label("安装 mas CLI", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!model.canInstallMasCLI || model.hasRunningJob)
                    }
                }
                if !mas.error.isEmpty {
                    WarningLine(text: mas.error)
                }
                if !mas.available {
                    InstallToolPrompt(
                        title: model.canInstallMasCLI ? "可通过 Homebrew 自动安装" : "需要先安装 Homebrew",
                        text: model.canInstallMasCLI
                            ? "点击安装会执行 brew install mas，完成后自动重新扫描 App Store 应用。"
                            : "当前未检测到可用的 Homebrew，无法自动安装 mas CLI。",
                        symbol: model.canInstallMasCLI ? "terminal" : "exclamationmark.lock"
                    )
                }
            } else {
                EmptyStateView(symbol: "bag", title: "等待扫描", text: "点击扫描后会显示 App Store 应用。")
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(apps) { app in
                        UpdateRow(package: .mas(app))
                    }
                }
            }
        }
        .padding(16)
    }
}
