import Foundation

/// Locates, loads and saves Touchy's JSON config files (`bindings.json`,
/// `settings.json`).
///
/// Each file is looked up in `~/.config/touchy` first, then in
/// `~/Library/Application Support/Touchy`, and read from the first place it
/// exists — so config can live in a dotfiles repo. A file that exists in neither
/// is created in `~/.config/touchy` if that directory exists, otherwise in
/// Application Support. Saves re-resolve the same way, so in-app edits always land
/// in the file the next launch will read (even if the user moved it while running).
struct ConfigFiles {
    let userConfigDirectory: URL
    let appSupportDirectory: URL

    static let bindings = "bindings.json"
    static let settings = "settings.json"

    static let standard = ConfigFiles(
        userConfigDirectory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/touchy", isDirectory: true),
        appSupportDirectory: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Touchy", isDirectory: true))

    /// Where `name` is read from and saved to right now.
    func url(for name: String) -> URL {
        let user = userConfigDirectory.appendingPathComponent(name)
        let appSupport = appSupportDirectory.appendingPathComponent(name)
        let fm = FileManager.default
        if fm.fileExists(atPath: user.path) { return user }
        if fm.fileExists(atPath: appSupport.path) { return appSupport }
        var isDir: ObjCBool = false
        let userDirExists = fm.fileExists(atPath: userConfigDirectory.path, isDirectory: &isDir) && isDir.boolValue
        return userDirExists ? user : appSupport
    }

    /// Decodes `name`, or returns nil if it doesn't exist or can't be parsed. An
    /// unparseable file is first copied to `<name>.bak`: the caller falls back to
    /// defaults and its next save would otherwise overwrite e.g. a hand edit with
    /// a typo in it.
    func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let url = url(for: name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let backup = url.appendingPathExtension("bak")
            try? data.write(to: backup, options: .atomic)
            NSLog("Touchy: couldn't parse \(url.path) (\(error)); saved a copy to \(backup.path) and using defaults")
            return nil
        }
    }

    /// Encodes `value` to `name` as pretty-printed JSON with sorted keys and a
    /// trailing newline, so the file diffs cleanly in version control.
    func save<T: Encodable>(_ value: T, to name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard var data = try? encoder.encode(value) else { return }
        data.append(0x0A)
        // Write through symlinks (dotfile managers often link the file into a repo):
        // an atomic write to the link itself would replace it with a plain file.
        let target = url(for: name).resolvingSymlinksInPath()
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch {
            NSLog("Touchy: couldn't save \(target.path): \(error.localizedDescription)")
        }
    }
}
