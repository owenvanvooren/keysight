//
//  ContentView.swift
//  keysight
//
//  Created by owen van vooren on 3/24/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var lightController: LightController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("keysight")
                .font(.title2.bold())

            Text("light up a strip at the bottom of every screen.")
                .foregroundStyle(.secondary)

            Button(lightController.isVisible ? "turn strip off" : "turn strip on") {
                lightController.toggle()
            }
            .buttonStyle(.borderedProminent)

            Stepper(value: $lightController.stripHeight, in: 48...220, step: 4) {
                Text("strip height: \(Int(lightController.stripHeight)) px")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("brightness: \(Int(lightController.brightness * 100))%")
                Slider(value: $lightController.brightness, in: 0.40...2.20)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("warmth: \(Int(lightController.warmth * 100))%")
                Slider(value: $lightController.warmth, in: 0.0...0.8)
            }

            Toggle("enable cursor hover cutout", isOn: $lightController.hoverCutoutEnabled)

            if lightController.hoverCutoutEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("cutout width: \(Int(lightController.hoverCutoutWidth)) px")
                    Slider(value: $lightController.hoverCutoutWidth, in: 120...420)
                }
            }

            Picker("keyboard shortcut", selection: Binding(
                get: { lightController.selectedShortcut },
                set: { lightController.setShortcut($0) }
            )) {
                ForEach(lightController.availableShortcuts) { shortcut in
                    Text(shortcut.title).tag(shortcut)
                }
            }

            Toggle(
                "launch at login",
                isOn: Binding(
                    get: { lightController.launchAtLoginEnabled },
                    set: { lightController.setLaunchAtLoginEnabled($0) }
                )
            )

            Text("global shortcut: \(lightController.shortcutDisplayName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView(lightController: LightController(registerHotKey: false))
}
