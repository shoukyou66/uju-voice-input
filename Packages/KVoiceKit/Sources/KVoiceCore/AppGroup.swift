import Foundation

/// The App Group shared by the app and the keyboard extension. Its identifier
/// comes from the `KVoiceAppGroup` Info.plist key, set from the build setting.
/// Sideloading tools (AltStore, SideStore) re-sign with a free account and
/// append the team ID to each group; the embedded provisioning profile then
/// names the group actually granted.
public enum AppGroup {
    public static let identifier: String = {
        let configured = Bundle.main.object(forInfoDictionaryKey: "KVoiceAppGroup") as? String
            ?? "group.io.github.kccarlos.kvoice.ios"
        return provisionedGroup(matching: configured) ?? configured
    }()

    /// The profile's group that is `configured` plus a suffix, if any.
    static func provisionedGroup(matching configured: String, bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return provisionedGroups(inProfile: data).first { $0.hasPrefix(configured + ".") }
    }

    /// The application groups a provisioning profile grants. The profile is
    /// a signed CMS envelope around a plain XML plist.
    static func provisionedGroups(inProfile data: Data) -> [String] {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data[start.lowerBound..<end.upperBound], format: nil
              ) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any]
        else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// The shared directory KVoice stores modes, history and handoff state
    /// in: the App Group container, or Application Support when the group
    /// is unavailable (tests, unsigned builds).
    public static var storageDirectory: URL {
        if let containerURL {
            return containerURL.appending(path: "KVoice", directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "KVoice", directoryHint: .isDirectory)
    }

    /// Files are readable after the first unlock, so App Intents work on a
    /// locked device (the Keychain uses `AfterFirstUnlock` too).
    public static var fileWriteOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        [.atomic]
        #endif
    }

    /// Creates a directory with the same data-protection class.
    public static func createProtectedDirectory(at url: URL) throws {
        #if os(iOS)
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        #else
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #endif
    }
}
