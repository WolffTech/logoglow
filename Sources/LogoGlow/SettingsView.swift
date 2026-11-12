// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import LogoGlowCore
import SwiftUI

struct SettingsView: View {
    let model: LogoModel
    @Bindable var updates: UpdateController

    var body: some View {
        Form {
            Section {
                AboutHeader()
            }
            Section("Brightness") {
                if model.isSupported {
                    brightnessRows
                } else {
                    Text("This Mac has no illuminated logo.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Check for updates automatically", isOn: $updates.automaticallyChecksForUpdates)
                Toggle("Download updates automatically", isOn: $updates.automaticallyDownloadsUpdates)
                    .disabled(!updates.automaticallyChecksForUpdates)
                LabeledContent("Software Update") {
                    Button("Check Now") { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text(updates.isAvailable
                    ? "Updates are downloaded from GitHub Releases and verified before they are installed."
                    : "Updates are available when running the installed app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!updates.isAvailable)
            Section {
                LabeledContent("License", value: "GPL-2.0-only")
                LabeledContent("Source Code") {
                    Link("github.com/WolffTech/logoglow", destination: AppInfo.sourceURL)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { updates.refresh() }
        .task {
            while !Task.isCancelled {
                model.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    @ViewBuilder
    private var brightnessRows: some View {
        if let state = model.state {
            LabeledContent("Logo Now", value: "\(Int(state.appliedNits.rounded())) nits")
        }
        LabeledContent {
            Button(model.isFullRangeUnlocked ? "Restore Limits…" : "Unlock…") {
                model.toggleFullRange()
            }
            .disabled(model.isChangingRange)
        } label: {
            Text("Full Brightness Range")
            Text(rangeDescription)
        }
    }

    private var rangeDescription: String {
        if model.isFullRangeUnlocked {
            return "Unlocked. Logo Glow can set any brightness from off to \(Int(FullRange.maxNits)) nits."
        }
        guard let state = model.state else {
            return "macOS limits logo brightness based on ambient light."
        }
        let range = "\(Int(state.minNitsRestriction.rounded()))–\(Int(state.maxNitsRestriction.rounded())) nits"
        return "macOS limits logo brightness based on ambient light, currently to \(range)."
    }
}

private struct AboutHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text("Logo Glow")
                    .font(.title2.weight(.semibold))
                Text(AppInfo.versionDescription)
                    .foregroundStyle(.secondary)
                Text("Take manual control of the illuminated Apple logo.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private enum AppInfo {
    static let sourceURL = URL(string: "https://github.com/WolffTech/logoglow")!

    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
        guard let build = info?["CFBundleVersion"] as? String else { return "Version \(version)" }
        return "Version \(version) (\(build))"
    }
}
