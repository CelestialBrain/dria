//
//  SettingsView.swift
//  dria
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            ModesTab()
                .environment(appState)
                .tabItem { Label("Modes", systemImage: "square.stack.3d.up") }

            AISettingsTab()
                .environment(appState)
                .tabItem { Label("AI Model", systemImage: "cpu") }

            CustomizationTab()
                .environment(appState)
                .tabItem { Label("Stealth", systemImage: "eye.slash") }

            GeneralSettingsTab()
                .environment(appState)
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 500, height: 420)
    }
}
