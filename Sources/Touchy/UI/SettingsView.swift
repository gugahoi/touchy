import SwiftUI

/// The Settings pane: general app options plus gesture-recognition tuning.
/// Recognizer changes apply live (via `GestureEngine`), so the footer's
/// last-gesture indicator can be used to try a value out immediately.
struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    @State private var launchAtLogin = LoginItem.isEnabled

    private typealias R = RecognizerSettings

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        // Revert the toggle if the system rejects the change.
                        if !LoginItem.setEnabled(newValue) {
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                LabeledContent("Version") {
                    Text(appVersion).textSelection(.enabled)
                }
            }

            Section("Swipes") {
                SettingSlider(
                    title: "Swipe distance",
                    value: $settings.recognizer.swipeThreshold,
                    range: R.swipeThresholdRange, step: 0.01,
                    format: { "\(percent($0)) of trackpad" },
                    help: "How far your fingers must travel before a swipe fires. Lower is more sensitive but easier to trigger by accident.")
                SettingSlider(
                    title: "Per-finger travel",
                    value: $settings.recognizer.fingerTravelRatio,
                    range: R.fingerTravelRatioRange, step: 0.05,
                    format: { $0 <= 0 ? "Off" : "\(percent($0)) of swipe" },
                    help: "At least 3 fingers must each move this share of the swipe distance. Stops 2-finger scrolls with a resting thumb or palm from counting as swipes. Lower it if real swipes get missed.")
            }

            Section("Taps") {
                SettingSlider(
                    title: "Max tap duration",
                    value: $settings.recognizer.tapMaxDuration,
                    range: R.tapMaxDurationRange, step: 0.05,
                    format: milliseconds,
                    help: "Touches held longer than this don't count as taps.")
                SettingSlider(
                    title: "Tap movement tolerance",
                    value: $settings.recognizer.tapMaxMovement,
                    range: R.tapMaxMovementRange, step: 0.01,
                    format: { "\(percent($0)) of trackpad" },
                    help: "How far fingers may drift during a tap and still count as one.")
            }

            Section("Timing") {
                SettingSlider(
                    title: "Cooldown between gestures",
                    value: $settings.recognizer.cooldown,
                    range: R.cooldownRange, step: 0.05,
                    format: { $0 <= 0 ? "None" : milliseconds($0) },
                    help: "Pause after a gesture fires before another can. Stops one motion firing twice; too long swallows quick repeats.")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        settings.recognizer = RecognizerSettings()
                    }
                    .disabled(settings.recognizer == RecognizerSettings())
                }
            }

            Section {
                ConfigFileRow(name: ConfigFiles.bindings)
                ConfigFileRow(name: ConfigFiles.settings)
            } header: {
                Text("Configuration Files")
            } footer: {
                Text("Touchy reads each file from ~/.config/touchy first, then Application Support, and saves changes back to the same file. Edits made outside the app apply after restarting Touchy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

/// Shows where a config file is read from / saved to, with a Finder shortcut.
private struct ConfigFileRow: View {
    let name: String

    var body: some View {
        let url = ConfigFiles.standard.url(for: name)
        let exists = FileManager.default.fileExists(atPath: url.path)
        let dirExists = FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
                     + (exists ? "" : "  (not created yet)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Show in Finder") {
                if exists {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    NSWorkspace.shared.open(url.deletingLastPathComponent())
                }
            }
            .controlSize(.small)
            .disabled(!exists && !dirExists)
        }
    }
}

private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
private func milliseconds(_ v: Double) -> String { "\(Int((v * 1000).rounded())) ms" }

/// e.g. "1.2.0 (40)" — stamped into the bundle by scripts/make-app.sh. A bare
/// `swift build` binary has no bundle Info.plist, hence the fallback.
private var appVersion: String {
    let info = Bundle.main.infoDictionary
    guard let version = info?["CFBundleShortVersionString"] as? String else {
        return "Development build"
    }
    guard let build = info?["CFBundleVersion"] as? String, build != version else {
        return version
    }
    return "\(version) (\(build))"
}

/// A labelled slider with its current value and an explanatory caption.
private struct SettingSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            // Snap to `step` manually rather than via Slider(step:), which draws a
            // tick mark per step on macOS.
            Slider(value: Binding(get: { value }, set: { value = snapped($0) }), in: range)
                .labelsHidden()
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    /// Rounds to `step`, then to 4 decimals so values compare equal to their
    /// literal defaults (keeps "Restore Defaults" state accurate).
    private func snapped(_ v: Double) -> Double {
        let s = (v / step).rounded() * step
        return min(max((s * 10_000).rounded() / 10_000, range.lowerBound), range.upperBound)
    }
}
