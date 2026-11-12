// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import SwiftUI

struct MenuContent: View {
    let model: LogoModel
    let updates: UpdateController
    @State private var draftBrightness = 0.5
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.isSupported {
                GlowPreview(intensity: model.previewIntensity(brightness: draftBrightness))
                Divider()
                modes
                brightnessSlider
            } else {
                Text("This Mac has no illuminated logo.")
                    .foregroundStyle(.secondary)
            }
            Divider()
            actions
        }
        .padding(14)
        .frame(width: 300)
        .onAppear {
            model.refresh()
            draftBrightness = model.brightness
        }
        .onChange(of: model.brightness) { _, brightness in
            draftBrightness = brightness
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Logo Glow")
                    .font(.headline)
                Text(model.status.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isSupported {
                Toggle("Control Logo", isOn: Binding(
                    get: { model.isControlling },
                    set: { model.setControlling($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }

    private var modes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mode")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(LightMode.allCases) { mode in
                    ModeTile(mode: mode, isSelected: true)
                }
            }
            .disabled(!model.canAdjustLight)
        }
    }

    private var brightnessSlider: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.min")
                .accessibilityLabel("Dimmer")
            Slider(value: $draftBrightness, in: 0...1) { editing in
                if !editing { model.setBrightness(draftBrightness) }
            }
            .controlSize(.large)
            .accessibilityLabel("Logo brightness")
            Image(systemName: "sun.max")
                .accessibilityLabel("Brighter")
        }
        .font(.title3)
        .foregroundStyle(.secondary)
        .disabled(!model.canAdjustLight)
    }

    private var actions: some View {
        VStack(spacing: 0) {
            if model.isSupported {
                MenuRow(model.isLightOn ? "Turn Logo Off" : "Turn Logo On") {
                    model.setLightOn(!model.isLightOn)
                }
                .disabled(!model.isControlling)
            }
            MenuRow("Logo Glow Settings…", shortcut: "⌘,") {
                NSApp.activate()
                openSettings()
            }
            .keyboardShortcut(",")
            if updates.isAvailable {
                MenuRow("Check for Updates…") {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheckForUpdates)
            }
            MenuRow("Quit Logo Glow", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.horizontal, -6)
    }
}

private struct GlowPreview: View {
    let intensity: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.85))
            RadialGradient(
                colors: [.white.opacity(0.45 * intensity), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 40 + 90 * intensity
            )
            Circle()
                .fill(Color(white: 0.22 + 0.78 * intensity))
                .frame(width: 56, height: 56)
                .shadow(color: .white.opacity(0.9 * intensity), radius: 6 + 14 * intensity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
        .frame(height: 150)
        .animation(.easeOut(duration: 0.25), value: intensity)
        .accessibilityHidden(true)
    }
}

private struct ModeTile: View {
    let mode: LightMode
    let isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: mode.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)))
            Text(mode.title)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quinary))
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MenuRow: View {
    let title: String
    let shortcut: String?
    let action: () -> Void

    init(_ title: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
    }
}

private struct MenuRowStyle: ButtonStyle {
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.primary.opacity(isHovered && isEnabled ? 0.1 : 0))
            )
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .onHover { isHovered = $0 }
    }
}
