import Foundation
import Testing
@testable import PasteMemo

@Suite("Local Backup Destination", .serialized)
struct LocalBackupDestinationTests {
    @Test("Reset to default clears bookmark and saved fallback path")
    func resetClearsEveryCustomDirectorySource() {
        let defaults = UserDefaults.standard
        let bookmarkKey = "backupDirectoryBookmark"
        let pathKey = "backupLocalPath"
        let previousBookmark = defaults.data(forKey: bookmarkKey)
        let previousPath = defaults.string(forKey: pathKey)
        defer {
            if let previousBookmark {
                defaults.set(previousBookmark, forKey: bookmarkKey)
            } else {
                defaults.removeObject(forKey: bookmarkKey)
            }
            if let previousPath {
                defaults.set(previousPath, forKey: pathKey)
            } else {
                defaults.removeObject(forKey: pathKey)
            }
        }

        defaults.set(Data([0x01]), forKey: bookmarkKey)
        defaults.set("/tmp/pastememo-custom-backup", forKey: pathKey)

        LocalBackupDestination.resetToDefault()

        #expect(defaults.data(forKey: bookmarkKey) == nil)
        #expect(defaults.string(forKey: pathKey) == nil)
        #expect(LocalBackupDestination.hasCustomDirectory == false)
    }
}
