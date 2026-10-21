import Foundation
import Combine

/// App settings (currently the recognizer tuning), persisted as `settings.json`
/// next to — but separate from — `bindings.json` (see `ConfigFiles` for where they
/// live), so resetting one never touches the other. Main-thread only:
/// `GestureEngine` forwards changes to the recognizer, which keeps its own
/// lock-protected copy for the callback thread.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    struct Persisted: Codable {
        var recognizer: RecognizerSettings

        init(recognizer: RecognizerSettings) {
            self.recognizer = recognizer
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            recognizer = (try? c.decodeIfPresent(RecognizerSettings.self, forKey: .recognizer))
                ?? RecognizerSettings()
        }
    }

    @Published var recognizer: RecognizerSettings

    private let files = ConfigFiles.standard
    private var saveSubscription: AnyCancellable?

    private init() {
        recognizer = files.load(Persisted.self, from: ConfigFiles.settings)?.recognizer
            ?? RecognizerSettings()
        if ProcessInfo.processInfo.environment["TOUCHY_DEBUG"] != nil {
            FileHandle.standardError.write(Data(
                "[touchy] loaded settings from \(files.url(for: ConfigFiles.settings).path): \(recognizer)\n".utf8))
        }
        // Sliders change the value continuously while dragging; coalesce the writes.
        saveSubscription = $recognizer
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] value in
                self?.files.save(Persisted(recognizer: value), to: ConfigFiles.settings)
            }
    }
}
