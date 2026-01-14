import Foundation
import AppKit

// MARK: - NSScreen Extensions
extension NSScreen {
    /// Returns a unique identifier for this screen
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }

    /// Returns a human-readable name for this screen
    var displayName: String {
        localizedName
    }

    /// Checks if this is the primary (main) display
    var isPrimary: Bool {
        self == NSScreen.main
    }
}

// MARK: - URL Extensions
extension URL {
    /// Returns the file size in bytes, or nil if unavailable
    var fileSize: Int64? {
        let resourceValues = try? resourceValues(forKeys: [.fileSizeKey])
        return resourceValues?.fileSize.map { Int64($0) }
    }

    /// Returns a human-readable file size string
    var fileSizeFormatted: String? {
        guard let size = fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Date Extensions
extension Date {
    /// Returns a relative date string (e.g., "Today", "Yesterday", "2 days ago")
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - NSImage Extensions
extension NSImage {
    /// Creates an NSImage from a CGImage with specified size
    convenience init(cgImage: CGImage, size: CGSize) {
        self.init(cgImage: cgImage, size: NSSize(width: size.width, height: size.height))
    }

    /// Resizes the image to fit within the specified size while maintaining aspect ratio
    func resized(to targetSize: NSSize) -> NSImage {
        let aspectRatio = size.width / size.height
        var newSize: NSSize

        if targetSize.width / targetSize.height > aspectRatio {
            newSize = NSSize(width: targetSize.height * aspectRatio, height: targetSize.height)
        } else {
            newSize = NSSize(width: targetSize.width, height: targetSize.width / aspectRatio)
        }

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        newImage.unlockFocus()

        return newImage
    }
}

// MARK: - Collection Extensions
extension Collection {
    /// Returns the element at the specified index if it is within bounds, otherwise nil
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - FileManager Extensions
extension FileManager {
    /// Creates a directory at the specified URL if it doesn't exist
    func createDirectoryIfNeeded(at url: URL) throws {
        if !fileExists(atPath: url.path) {
            try createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// Returns the total size of a directory in bytes
    func directorySize(at url: URL) -> Int64 {
        guard let enumerator = enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }

        return totalSize
    }
}

// MARK: - NSWorkspace Extensions
extension NSWorkspace {
    /// Opens the specified URL in Finder and selects it
    func revealInFinder(_ url: URL) {
        selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
}

