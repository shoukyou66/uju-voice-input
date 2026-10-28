import Foundation
import Testing
@testable import KVoiceCore
@testable import KVoiceKit

@Test func appGroupIdentifierHasGroupPrefix() {
    #expect(AppGroup.identifier.hasPrefix("group."))
}

@Test func provisionedGroupsReadsProfileEntitlements() {
    let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>Entitlements</key><dict>
        <key>com.apple.security.application-groups</key>
        <array><string>group.example.app.ABCDE12345</string></array>
        </dict></dict></plist>
        """
    var profile = Data([0x30, 0x80, 0x06, 0x09])
    profile.append(Data(plist.utf8))
    profile.append(Data([0x00, 0x00]))
    #expect(AppGroup.provisionedGroups(inProfile: profile) == ["group.example.app.ABCDE12345"])
    #expect(AppGroup.provisionedGroups(inProfile: Data("no plist".utf8)).isEmpty)
}
