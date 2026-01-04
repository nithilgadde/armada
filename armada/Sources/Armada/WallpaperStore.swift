import Foundation
import AppKit

// MARK: - Wallpaper Store
/// Handles persistence of wallpaper library and settings using JSON storage
/// Stores data in Application Support directory for sandbox compatibility
final class WallpaperStore {
    static let shared = WallpaperStore()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Storage file names
    private let wallpapersFileName = "wallpapers.json"
    private let settingsFileName = "settings.json"
    private let wallpapersFolderName = "Wallpapers"

    // MARK: - Directory Paths

    /// Application Support directory for this app
    private var appSupportDirectory: URL {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("Armada", isDirectory: true)

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: appSupport.path) {
            try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }

        return appSupport
    }

    /// Directory where wallpaper files are copied to
    var wallpapersDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent(wallpapersFolderName, isDirectory: true)

        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        return dir
    }

    private var wallpapersFileURL: URL {
        appSupportDirectory.appendingPathComponent(wallpapersFileName)
    }

    private var settingsFileURL: URL {
        appSupportDirectory.appendingPathComponent(settingsFileName)
    }

    // MARK: - Initialization

    private init() {
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Wallpaper Operations

    /// Loads all wallpapers from storage
    func loadWallpapers() -> [Wallpaper] {
        guard fileManager.fileExists(atPath: wallpapersFileURL.path),
              let data = try? Data(contentsOf: wallpapersFileURL),
              let wallpapers = try? decoder.decode([Wallpaper].self, from: data) else {
            return []
        }

        // Filter out wallpapers whose files no longer exist
        return wallpapers.filter { wallpaper in
            let localURL = localURL(for: wallpaper)
            return fileManager.fileExists(atPath: localURL.path)
        }
    }

    /// Saves wallpapers to storage
    func saveWallpapers(_ wallpapers: [Wallpaper]) {
        guard let data = try? encoder.encode(wallpapers) else { return }
        try? data.write(to: wallpapersFileURL, options: .atomic)
    }

    /// Imports a wallpaper file into the library
    /// - Parameter url: Source URL of the wallpaper file
    /// - Returns: The created Wallpaper if successful
    func importWallpaper(from url: URL) -> Wallpaper? {
        guard let wallpaper = Wallpaper.from(url: url) else { return nil }

        let destinationURL = localURL(for: wallpaper)

        // Start accessing security-scoped resource if needed
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            // Remove existing file if present
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            // Copy file to app's storage
            try fileManager.copyItem(at: url, to: destinationURL)
            return wallpaper
        } catch {
            print("Failed to import wallpaper: \(error.localizedDescription)")
            return nil
        }
    }

    /// Removes a wallpaper from storage
    func removeWallpaper(_ wallpaper: Wallpaper) {
        let localURL = localURL(for: wallpaper)
        try? fileManager.removeItem(at: localURL)
    }

    /// Gets the local URL for a wallpaper file
    func localURL(for wallpaper: Wallpaper) -> URL {
        wallpapersDirectory.appendingPathComponent("\(wallpaper.id.uuidString).\(wallpaper.fileExtension)")
    }

    // MARK: - Settings Operations

    /// Loads app settings from storage
    func loadSettings() -> AppSettings {
        guard fileManager.fileExists(atPath: settingsFileURL.path),
              let data = try? Data(contentsOf: settingsFileURL),
              let settings = try? decoder.decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    /// Saves app settings to storage
    func saveSettings(_ settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: settingsFileURL, options: .atomic)
    }
}

// MARK: - App Settings
/// Stores user preferences and app state
struct AppSettings: Codable {
    var launchAtLogin: Bool = false
    var lastActiveWallpaperID: UUID?
    var displayAssignments: [DisplayAssignment] = []
    var pauseWhenNotVisible: Bool = true
    var muteAudio: Bool = true

    /// Gets the wallpaper ID assigned to a specific display
    func wallpaperID(for displayID: String) -> UUID? {
        displayAssignments.first { $0.displayID == displayID }?.wallpaperID
    }

    /// Sets the wallpaper for a specific display
    mutating func setWallpaper(_ wallpaperID: UUID?, for displayID: String) {
        if let index = displayAssignments.firstIndex(where: { $0.displayID == displayID }) {
            displayAssignments[index].wallpaperID = wallpaperID
        } else {
            displayAssignments.append(DisplayAssignment(displayID: displayID, wallpaperID: wallpaperID))
        }
    }
}
