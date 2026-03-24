//
//  keysightApp.swift
//  keysight
//
//  Created by owen van vooren on 3/24/26.
//

import SwiftUI
import AppKit

@main
struct keysightApp: App {
    @StateObject private var lightController = LightController()
    
    private var currentMenuIconName: String {
        lightController.isVisible ? "menu-icon-activated" : "menu-icon"
    }
    
    private var fallbackSymbolName: String {
        lightController.isVisible ? "sun.max.fill" : "sun.min"
    }
    
    var body: some Scene {
        MenuBarExtra {
            Button(lightController.isVisible ? "turn strip off" : "turn strip on") {
                lightController.toggle()
            }
            
            Divider()
            Text("global shortcut: \(lightController.shortcutDisplayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Menu("keyboard shortcut") {
                ForEach(lightController.availableShortcuts) { shortcut in
                    Button {
                        lightController.setShortcut(shortcut)
                    } label: {
                        if shortcut == lightController.selectedShortcut {
                            Label(shortcut.title, systemImage: "checkmark")
                        } else {
                            Text(shortcut.title)
                        }
                    }
                }
            }
            
            Toggle(
                "launch at login",
                isOn: Binding(
                    get: { lightController.launchAtLoginEnabled },
                    set: { lightController.setLaunchAtLoginEnabled($0) }
                )
            )
            
            Divider()
            SettingsLink {
                Text("open settings…")
            }
            
            Button("reset preferences") {
                lightController.resetPreferences()
            }
            
            Divider()
            Button("quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(lightController.isVisible ? "menu-icon-activated" : "menu-icon")
        }
        
        Settings {
            ContentView(lightController: lightController)
                .frame(width: 360)
                .padding(20)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
    }
}
