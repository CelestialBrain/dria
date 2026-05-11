//
//  CustomizationTab.swift
//  dria
//

import SwiftUI

struct CustomizationTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Stealth Presets") {
                HStack(spacing: 12) {
                    StealthPresetButton(label: "Full", icon: "eye", opacity: 1.0, current: state.marqueeOpacity) {
                        state.marqueeOpacity = 1.0
                    }
                    StealthPresetButton(label: "Subtle", icon: "eye.slash", opacity: 0.5, current: state.marqueeOpacity) {
                        state.marqueeOpacity = 0.5
                    }
                    StealthPresetButton(label: "Faint", icon: "cloud", opacity: 0.25, current: state.marqueeOpacity) {
                        state.marqueeOpacity = 0.25
                    }
                    StealthPresetButton(label: "Ghost", icon: "eye.slash.fill", opacity: 0.1, current: state.marqueeOpacity) {
                        state.marqueeOpacity = 0.1
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Text Visibility") {
                HStack {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(.secondary)
                    Slider(value: $state.marqueeOpacity, in: 0.05...1.0, step: 0.05)
                    Image(systemName: "eye")
                        .foregroundStyle(.secondary)
                }
                Text("Opacity: \(Int(state.marqueeOpacity * 100))% — \(opacityLabel(state.marqueeOpacity))")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Marquee") {
                HStack {
                    Text("Text width")
                    Slider(value: .init(
                        get: { Double(state.marqueeWidth) },
                        set: { state.marqueeWidth = Int($0) }
                    ), in: 10...50, step: 5)
                    Text("\(state.marqueeWidth)")
                        .font(.caption).monospacedDigit()
                        .frame(width: 25)
                }
                Text("Characters visible in menu bar. Smaller = more discreet.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Click to Copy") {
                Picker("When clicking the icon, copy:", selection: $state.copyMode) {
                    Text("Short answer only").tag("short")
                    Text("Full explanation").tag("full")
                    Text("Marquee text (what's scrolling)").tag("marquee")
                }
                .pickerStyle(.radioGroup)
            }

            Section("Safety") {
                Toggle("Lock chat window", isOn: $state.lockPopover)
                Text("Prevents accidental popover. Use ⌘⌥3 for inline chat.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func opacityLabel(_ v: Double) -> String {
        if v < 0.15 { return "Ghost mode — nearly invisible" }
        if v < 0.3 { return "Faint — very hard to read" }
        if v < 0.5 { return "Subtle — blends with dark menus" }
        if v < 0.8 { return "Visible — readable but understated" }
        return "Full — normal text brightness"
    }
}

private struct StealthPresetButton: View {
    let label: String
    let icon: String
    let opacity: Double
    let current: Double
    let action: () -> Void

    private var isSelected: Bool {
        abs(current - opacity) < 0.06
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
