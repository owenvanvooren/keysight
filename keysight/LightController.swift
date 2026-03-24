//
//  LightController.swift
//  keysight
//
//  Created by owen van vooren on 3/24/26.
//

import AppKit
import Carbon
import ServiceManagement
import SwiftUI
import Combine

@MainActor
final class LightController: ObservableObject {
    private enum PrefKey {
        static let selectedShortcut = "selected_shortcut"
        static let stripHeight = "strip_height"
        static let brightness = "brightness"
        static let warmth = "warmth"
        static let hoverCutoutEnabled = "hover_cutout_enabled"
        static let hoverCutoutWidth = "hover_cutout_width"
    }
    
    @Published private(set) var isVisible = false
    @Published private(set) var selectedShortcut: ShortcutOption = .commandOptionSpace
    @Published private(set) var launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
    @Published var stripHeight: CGFloat = 90 {
        didSet {
            UserDefaults.standard.set(Double(stripHeight), forKey: PrefKey.stripHeight)
            if isVisible {
                refreshVisibleWindows()
            }
        }
    }
    @Published var brightness: Double = 1.35 {
        didSet {
            UserDefaults.standard.set(brightness, forKey: PrefKey.brightness)
            if isVisible {
                updateAllWindowViews()
            }
        }
    }
    @Published var warmth: Double = 0.18 {
        didSet {
            UserDefaults.standard.set(warmth, forKey: PrefKey.warmth)
            if isVisible {
                updateAllWindowViews()
            }
        }
    }
    @Published var hoverCutoutEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(hoverCutoutEnabled, forKey: PrefKey.hoverCutoutEnabled)
            if isVisible {
                updateAllWindowViews()
            }
        }
    }
    @Published var hoverCutoutWidth: CGFloat = 220 {
        didSet {
            UserDefaults.standard.set(Double(hoverCutoutWidth), forKey: PrefKey.hoverCutoutWidth)
            if isVisible {
                updateAllWindowViews()
            }
        }
    }
    
    private struct StripWindowEntry {
        let screen: NSScreen
        let window: NSPanel
        let host: NSHostingView<StripLightView>
        var hoverCutoutPoint: CGPoint?
    }
    
    private var stripWindows: [StripWindowEntry] = []
    private let hotKeyManager = HotKeyManager()
    private var screenChangeObserver: NSObjectProtocol?
    private var cursorUpdateTimer: Timer?
    private let registerHotKey: Bool
    
    init(registerHotKey: Bool = true) {
        self.registerHotKey = registerHotKey
        loadPersistedPreferences()
        
        if registerHotKey {
            hotKeyManager.onHotKeyPressed = { [weak self] in
                MainActor.assumeIsolated {
                    self?.toggle()
                }
            }
            registerShortcut()
        }
        
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                self.refreshVisibleWindows()
            }
        }
    }
    
    deinit {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
    }
    
    var availableShortcuts: [ShortcutOption] {
        ShortcutOption.allCases
    }
    
    var shortcutDisplayName: String {
        selectedShortcut.title
    }
    
    func toggle() {
        isVisible ? hideStrip() : showStrip()
    }
    
    func setShortcut(_ shortcut: ShortcutOption) {
        selectedShortcut = shortcut
        UserDefaults.standard.set(shortcut.rawValue, forKey: PrefKey.selectedShortcut)
        registerShortcut()
    }
    
    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        LaunchAtLoginManager.setEnabled(enabled)
        launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
    }
    
    func resetPreferences() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: PrefKey.selectedShortcut)
        defaults.removeObject(forKey: PrefKey.stripHeight)
        defaults.removeObject(forKey: PrefKey.brightness)
        defaults.removeObject(forKey: PrefKey.warmth)
        defaults.removeObject(forKey: PrefKey.hoverCutoutEnabled)
        defaults.removeObject(forKey: PrefKey.hoverCutoutWidth)
        
        setShortcut(.commandOptionSpace)
        stripHeight = 90
        brightness = 1.35
        warmth = 0.18
        hoverCutoutEnabled = true
        hoverCutoutWidth = 220
        setLaunchAtLoginEnabled(false)
    }
    
    private func showStrip() {
        guard !isVisible else { return }
        
        stripWindows = NSScreen.screens.map(makeStripWindow(for:))
        for entry in stripWindows {
            entry.window.orderFrontRegardless()
        }
        
        isVisible = true
        startCursorTracking()
        updateCursorHoverState()
    }
    
    private func hideStrip() {
        stopCursorTracking()
        for entry in stripWindows {
            entry.window.orderOut(nil)
        }
        stripWindows.removeAll()
        isVisible = false
    }
    
    private func refreshVisibleWindows() {
        hideStrip()
        showStrip()
    }
    
    private func makeStripWindow(for screen: NSScreen) -> StripWindowEntry {
        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: stripHeight
        )
        
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        
        let host = NSHostingView(rootView: makeStripLightView(hoverCutoutPoint: nil))
        panel.contentView = host
        return StripWindowEntry(screen: screen, window: panel, host: host, hoverCutoutPoint: nil)
    }
    
    private func makeStripLightView(hoverCutoutPoint: CGPoint?) -> StripLightView {
        StripLightView(
            brightness: brightness,
            warmth: warmth,
            stripHeight: stripHeight,
            hoverCutoutEnabled: hoverCutoutEnabled,
            hoverCutoutWidth: hoverCutoutWidth,
            hoverCutoutPoint: hoverCutoutPoint
        )
    }
    
    private func updateAllWindowViews() {
        for index in stripWindows.indices {
            stripWindows[index].host.rootView = makeStripLightView(hoverCutoutPoint: stripWindows[index].hoverCutoutPoint)
        }
    }
    
    private func startCursorTracking() {
        stopCursorTracking()
        cursorUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateCursorHoverState()
            }
        }
        
        if let cursorUpdateTimer {
            RunLoop.main.add(cursorUpdateTimer, forMode: .common)
        }
    }
    
    private func stopCursorTracking() {
        cursorUpdateTimer?.invalidate()
        cursorUpdateTimer = nil
    }
    
    private func updateCursorHoverState() {
        let cursor = NSEvent.mouseLocation
        for index in stripWindows.indices {
            let frame = stripWindows[index].window.frame
            let isInsideX = cursor.x >= frame.minX && cursor.x <= frame.maxX
            let isNearStripY = cursor.y >= frame.minY - 2 && cursor.y <= frame.maxY + 2
            
            let newHoverPoint: CGPoint? = if isInsideX && isNearStripY {
                CGPoint(
                    x: cursor.x - frame.minX,
                    y: frame.maxY - cursor.y
                )
            } else {
                nil
            }
            
            if stripWindows[index].hoverCutoutPoint != newHoverPoint {
                stripWindows[index].hoverCutoutPoint = newHoverPoint
                stripWindows[index].host.rootView = makeStripLightView(hoverCutoutPoint: newHoverPoint)
            }
        }
    }
    
    private func registerShortcut() {
        guard registerHotKey else { return }
        hotKeyManager.register(keyCode: selectedShortcut.keyCode, modifiers: selectedShortcut.modifiers)
    }
    
    private func loadPersistedPreferences() {
        let defaults = UserDefaults.standard
        
        if let storedShortcut = defaults.string(forKey: PrefKey.selectedShortcut),
           let shortcut = ShortcutOption(rawValue: storedShortcut) {
            selectedShortcut = shortcut
        }
        
        let storedStripHeight = defaults.double(forKey: PrefKey.stripHeight)
        if storedStripHeight > 0 {
            stripHeight = CGFloat(storedStripHeight)
        }
        
        let storedBrightness = defaults.double(forKey: PrefKey.brightness)
        if storedBrightness > 0 {
            brightness = storedBrightness
        }
        
        let storedWarmth = defaults.double(forKey: PrefKey.warmth)
        if storedWarmth > 0 {
            warmth = storedWarmth
        }
        
        if defaults.object(forKey: PrefKey.hoverCutoutEnabled) != nil {
            hoverCutoutEnabled = defaults.bool(forKey: PrefKey.hoverCutoutEnabled)
        }
        
        let storedCutoutWidth = defaults.double(forKey: PrefKey.hoverCutoutWidth)
        if storedCutoutWidth > 0 {
            hoverCutoutWidth = CGFloat(storedCutoutWidth)
        }
    }
}

private final class HotKeyManager {
    var onHotKeyPressed: (@Sendable () -> Void)?
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    
    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onHotKeyPressed?()
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
        
        let hotKeyID = EventHotKeyID(signature: OSType(0x4B595347), id: 1)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
    
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
    
    deinit {
        unregister()
    }
}

enum ShortcutOption: String, CaseIterable, Identifiable {
    case controlOptionL
    case controlOptionSpace
    case commandOptionL
    case commandOptionSpace
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .controlOptionL:
            return "control + option + l"
        case .controlOptionSpace:
            return "control + option + space"
        case .commandOptionL:
            return "command + option + l"
        case .commandOptionSpace:
            return "command + option + space"
        }
    }
    
    var keyCode: UInt32 {
        switch self {
        case .controlOptionL, .commandOptionL:
            return UInt32(kVK_ANSI_L)
        case .controlOptionSpace, .commandOptionSpace:
            return UInt32(kVK_Space)
        }
    }
    
    var modifiers: UInt32 {
        switch self {
        case .controlOptionL, .controlOptionSpace:
            return UInt32(controlKey | optionKey)
        case .commandOptionL, .commandOptionSpace:
            return UInt32(cmdKey | optionKey)
        }
    }
}

enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }
    
    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Failed to update launch-at-login state: \(error.localizedDescription)")
        }
    }
}

private struct StripLightView: View {
    let brightness: Double
    let warmth: Double
    let stripHeight: CGFloat
    let hoverCutoutEnabled: Bool
    let hoverCutoutWidth: CGFloat
    let hoverCutoutPoint: CGPoint?
    
    private var clampedBrightness: Double {
        min(max(brightness, 0.2), 2.4)
    }
    
    private var tintColor: Color {
        Color(
            red: 1.00,
            green: 1.00 - (0.08 * warmth),
            blue: 1.00 - (0.24 * warmth)
        )
    }
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(tintColor.opacity(0.42 * clampedBrightness))
            
            LinearGradient(
                colors: [
                    Color.white.opacity(0.48 * clampedBrightness),
                    tintColor.opacity(0.85 * clampedBrightness)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            Rectangle()
                .fill(Color.white.opacity(0.35 * min(clampedBrightness, 1.8)))
                .frame(height: min(22, stripHeight * 0.28))
                .blur(radius: 10)
                .offset(y: -stripHeight * 0.30)
        }
        .overlay {
            if hoverCutoutEnabled, let hoverCutoutPoint {
                RadialGradient(
                    colors: [
                        .white.opacity(1.0),
                        .white.opacity(0.75),
                        .white.opacity(0.30),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: hoverCutoutWidth * 0.5
                )
                .frame(width: hoverCutoutWidth, height: hoverCutoutWidth)
                .position(x: hoverCutoutPoint.x, y: hoverCutoutPoint.y)
                .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .ignoresSafeArea()
    }
}
