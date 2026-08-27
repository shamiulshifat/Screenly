import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    private enum Keys {
        static let saveDirectoryPath = "framecast.saveDirectoryPath"
    }

    @Published var saveDirectoryPath: String? {
        didSet {
            UserDefaults.standard.set(saveDirectoryPath, forKey: Keys.saveDirectoryPath)
        }
    }

    init() {
        saveDirectoryPath = UserDefaults.standard.string(forKey: Keys.saveDirectoryPath)
    }

    var saveDirectoryURL: URL? {
        guard let saveDirectoryPath else { return nil }
        return URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
    }
}
