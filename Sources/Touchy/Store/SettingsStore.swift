import Foundation
import Combine

/// App settings (currently the recognizer tuning), persisted as JSON in
/// Application Support next to — but separate from — `bindings.json`, so resetting
/// one never touches the other. Main-thread only: `GestureEngine` forwards changes
/// to the recognizer, which keeps its own lock-protected copy for the callback thread.
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

    private let fileURL = AppSupport.fileURL("settings.json")
    private var saveSubscription: AnyCancellable?

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {
            recognizer = decoded.recognizer
        } else {
            recognizer = RecognizerSettings()
        }
        if ProcessInfo.processInfo.environment["TOUCHY_DEBUG"] != nil {
            FileHandle.standardError.write(Data("[touchy] loaded settings: \(recognizer)\n".utf8))
        }
        // Sliders change the value continuously while dragging; coalesce the writes.
        saveSubscription = $recognizer
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] value in self?.save(value) }
    }

    private func save(_ recognizer: RecognizerSettings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(Persisted(recognizer: recognizer)) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
