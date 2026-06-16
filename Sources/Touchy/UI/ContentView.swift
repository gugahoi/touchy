import SwiftUI

struct ContentView: View {
    @ObservedObject var store = BindingStore.shared
    @ObservedObject var engine = GestureEngine.shared
    @StateObject private var recorder = KeyRecorder()
    @State private var accessibilityTrusted = Permissions.hasAccessibility
    @State private var launchAtLogin = LoginItem.isEnabled

    private let permissionTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var swipes: [Gesture] { Gesture.all.filter { $0.kind == .swipe } }
    private var taps: [Gesture] { Gesture.all.filter { $0.kind == .tap } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            optionsBar
            Divider()
            if !accessibilityTrusted { permissionBanner }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    conflictNote
                    section("Swipes", gestures: swipes)
                    section("Taps", gestures: taps)
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 460, height: 560)
        .onReceive(permissionTimer) { _ in
            accessibilityTrusted = Permissions.hasAccessibility
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "hand.point.up.left.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Touchy").font(.headline)
                Text("Map trackpad gestures to keyboard shortcuts")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Enabled", isOn: $store.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(12)
    }

    private var optionsBar: some View {
        Toggle(isOn: $launchAtLogin) {
            Text("Launch at login").font(.subheadline)
        }
        .toggleStyle(.checkbox)
        .onChange(of: launchAtLogin) { newValue in
            // Revert the toggle if the system rejects the change.
            if !LoginItem.setEnabled(newValue) {
                launchAtLogin = LoginItem.isEnabled
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility permission required").font(.subheadline).bold()
                Text("Touchy needs Accessibility access to send keystrokes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Grant…") {
                Permissions.promptForAccessibility()
                Permissions.openAccessibilitySettings()
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }

    private var conflictNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text("Gestures marked ⚠︎ are also used by macOS (Mission Control, spaces, look-up). To avoid both firing, disable them in System Settings ▸ Trackpad, or prefer 5-finger gestures.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section(_ title: String, gestures: [Gesture]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(spacing: 6) {
                ForEach(gestures) { gesture in
                    GestureRow(gesture: gesture, store: store, recorder: recorder)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            lastGestureLabel
            Spacer()
            Button("Quit Touchy") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
        .padding(10)
    }

    @ViewBuilder private var lastGestureLabel: some View {
        if let last = engine.lastGesture {
            HStack(spacing: 6) {
                Circle()
                    .fill(engine.lastGestureFired ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text("Last: \(last.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !engine.lastGestureFired {
                    Text("(unbound)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .id(engine.lastGestureAt)
        } else {
            Text("Try a gesture on the trackpad…")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }
}

private struct GestureRow: View {
    let gesture: Gesture
    @ObservedObject var store: BindingStore
    @ObservedObject var recorder: KeyRecorder

    private var isRecording: Bool { recorder.recordingID == gesture.id }
    private var action: GestureAction? { store.action(for: gesture) }

    var body: some View {
        HStack(spacing: 10) {
            icon
            Text(gesture.displayName)
            if gesture.conflictsWithSystemDefault {
                Text("⚠︎").help("Also used by macOS by default")
            }
            Spacer()
            actionControl
            if action != nil {
                Button {
                    store.setAction(nil, for: gesture)
                } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Clear binding")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }

    private var icon: some View {
        Group {
            if gesture.kind == .swipe, let dir = gesture.direction {
                Image(systemName: dir.symbol)
            } else {
                Image(systemName: "hand.tap")
            }
        }
        .frame(width: 16)
        .foregroundStyle(.secondary)
    }

    // Common click presets offered in the menu.
    private static let clickPresets: [MouseClick] = [
        MouseClick(button: .left),
        MouseClick(button: .left, command: true),
        MouseClick(button: .left, option: true),
        MouseClick(button: .left, control: true),
        MouseClick(button: .left, shift: true),
        MouseClick(button: .right),
        MouseClick(button: .middle),
    ]

    @ViewBuilder private var actionControl: some View {
        if isRecording {
            Button {
                recorder.stop()
            } label: {
                Text("Press keys…")
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 110)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.bordered)
            .help("Press a shortcut, or Esc to cancel")
        } else {
            Menu {
                Button("Record Keyboard Shortcut…") {
                    recorder.startRecording(for: gesture.id) { captured in
                        store.setAction(.key(captured), for: gesture)
                    }
                }
                Menu("Mouse Click") {
                    ForEach(Self.clickPresets, id: \.self) { preset in
                        Button(preset.display) {
                            store.setAction(.click(preset), for: gesture)
                        }
                    }
                }
            } label: {
                Text(action?.display ?? "Set action")
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 110)
                    .foregroundStyle(action == nil ? .secondary : .primary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}
