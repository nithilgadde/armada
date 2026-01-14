import Foundation
import UniformTypeIdentifiers

// MARK: - Wallpaper Model
/// Represents a single wallpaper item with its metadata and file information
struct Wallpaper: Identifiable, Codable, Hashable {
    let id: UUID
    let fileName: String
    let fileExtension: String
    let dateAdded: Date
    let originalURL: URL

    /// The type of wallpaper based on file extension
    var type: WallpaperType {
        WallpaperType(from: fileExtension)
    }

    /// Display name without extension
    var displayName: String {
        fileName
    }

    /// Full file name with extension
    var fullFileName: String {
        "\(fileName).\(fileExtension)"
    }

    init(id: UUID = UUID(), fileName: String, fileExtension: String, dateAdded: Date = Date(), originalURL: URL) {
        self.id = id
        self.fileName = fileName
        self.fileExtension = fileExtension.lowercased()
        self.dateAdded = dateAdded
        self.originalURL = originalURL
    }

    /// Creates a Wallpaper from a file URL
    static func from(url: URL) -> Wallpaper? {
        let ext = url.pathExtension.lowercased()
        guard WallpaperType(from: ext) != .unknown else { return nil }

        let fileName = url.deletingPathExtension().lastPathComponent
        return Wallpaper(
            fileName: fileName,
            fileExtension: ext,
            originalURL: url
        )
    }
}

// MARK: - Wallpaper Type
/// Supported wallpaper formats
enum WallpaperType: String, Codable {
    case mp4
    case gif
    case unknown

    init(from extension: String) {
        switch `extension`.lowercased() {
        case "mp4", "m4v", "mov":
            self = .mp4
        case "gif":
            self = .gif
        default:
            self = .unknown
        }
    }

    var supportedExtensions: [String] {
        switch self {
        case .mp4:
            return ["mp4", "m4v", "mov"]
        case .gif:
            return ["gif"]
        case .unknown:
            return []
        }
    }

    static var allSupportedExtensions: [String] {
        WallpaperType.mp4.supportedExtensions + WallpaperType.gif.supportedExtensions
    }

    static var supportedUTTypes: [UTType] {
        [.mpeg4Movie, .movie, .gif]
    }
}

// MARK: - Display Assignment
/// Tracks which wallpaper is assigned to which display
struct DisplayAssignment: Codable, Identifiable {
    var id: String { displayID }
    let displayID: String
    var wallpaperID: UUID?

    init(displayID: String, wallpaperID: UUID? = nil) {
        self.displayID = displayID
        self.wallpaperID = wallpaperID
    }
}
