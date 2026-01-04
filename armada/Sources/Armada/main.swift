import Foundation
import ArgumentParser

// MARK: - Main CLI Entry Point
@main
struct Armada: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "armada",
        abstract: "Native macOS live wallpaper manager",
        discussion: """
            Set animated videos and GIFs as your macOS desktop wallpaper.

            EXAMPLES:
              Set wallpaper on all displays:
                armada set ~/Videos/cool.mp4
                armada set ~/Videos/cool.mp4 --display all

              Set wallpaper on specific display:
                armada set ~/Videos/video1.mp4 --display 1
                armada set ~/Videos/video2.mp4 --display 2

              Different wallpapers per display:
                armada set ~/Videos/ocean.mp4 -d 1
                armada set ~/Videos/forest.mp4 -d 2

              Remove wallpaper:
                armada unset              # Remove from all displays
                armada unset --display 1  # Remove from display 1

              Configuration:
                armada config --always-on     # Keep playing when apps are focused
                armada config --auto-pause    # Pause when desktop hidden (default)
                armada config --auto-resize   # Resize video to fit screen (default)
                armada config --no-resize     # Keep original video size

              Daemon control:
                armada start    # Start the wallpaper daemon
                armada stop     # Stop daemon and remove wallpapers
                armada status   # Show current status

              Library management:
                armada add ~/Videos/new.mp4   # Add to library
                armada list                   # List saved wallpapers
                armada remove "wallpaper"     # Remove from library
            """,
        version: "1.0.0",
        subcommands: [
            Start.self,
            Stop.self,
            Set.self,
            Unset.self,
            Add.self,
            Remove.self,
            List.self,
            Status.self,
            Config.self,
        ],
        defaultSubcommand: Status.self
    )
}

// MARK: - Start Command
struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the wallpaper daemon"
    )

    @Flag(name: .shortAndLong, help: "Run in foreground (don't daemonize)")
    var foreground = false

    func run() throws {
        if foreground {
            print("Starting Armada in foreground mode...")
            DaemonManager.shared.runInForeground()
        } else {
            try DaemonManager.shared.start()
            print("✓ Armada daemon started")
        }
    }
}

// MARK: - Stop Command
struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop the wallpaper daemon and remove all wallpapers"
    )

    func run() throws {
        try DaemonManager.shared.stop()
        print("✓ Armada daemon stopped")
    }
}

// MARK: - Set Command
struct Set: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Set a video or GIF as wallpaper"
    )

    @Argument(help: "Path to MP4, MOV, or GIF file")
    var path: String

    @Option(name: .shortAndLong, help: "Display number (1, 2, etc.) or 'all'")
    var display: String = "all"

    func run() throws {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("File not found: \(path)")
        }

        let ext = url.pathExtension.lowercased()
        guard ["mp4", "m4v", "mov", "gif"].contains(ext) else {
            throw ValidationError("Unsupported format. Use MP4, MOV, or GIF files.")
        }

        // Ensure daemon is running
        if !DaemonManager.shared.isRunning {
            try DaemonManager.shared.start()
        }

        // Send command to daemon
        try DaemonManager.shared.sendCommand(.setWallpaper(path: url.path, display: display))
        print("✓ Wallpaper set: \(url.lastPathComponent)")
    }
}

// MARK: - Unset Command
struct Unset: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove wallpaper from display(s)"
    )

    @Option(name: .shortAndLong, help: "Display number (1, 2, etc.) or 'all'")
    var display: String = "all"

    func run() throws {
        guard DaemonManager.shared.isRunning else {
            print("Daemon is not running")
            return
        }

        try DaemonManager.shared.sendCommand(.unsetWallpaper(display: display))
        print("✓ Wallpaper removed")
    }
}

// MARK: - Add Command
struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a wallpaper to the library"
    )

    @Argument(help: "Path to MP4, MOV, or GIF file")
    var path: String

    func run() throws {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("File not found: \(path)")
        }

        if let wallpaper = WallpaperStore.shared.importWallpaper(from: url) {
            var wallpapers = WallpaperStore.shared.loadWallpapers()
            wallpapers.append(wallpaper)
            WallpaperStore.shared.saveWallpapers(wallpapers)
            print("✓ Added to library: \(wallpaper.displayName)")
        } else {
            throw ValidationError("Failed to import wallpaper")
        }
    }
}

// MARK: - Remove Command
struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove a wallpaper from the library"
    )

    @Argument(help: "Wallpaper name or ID")
    var identifier: String

    func run() throws {
        var wallpapers = WallpaperStore.shared.loadWallpapers()

        guard let index = wallpapers.firstIndex(where: {
            $0.displayName.lowercased().contains(identifier.lowercased()) ||
            $0.id.uuidString.lowercased().hasPrefix(identifier.lowercased())
        }) else {
            throw ValidationError("Wallpaper not found: \(identifier)")
        }

        let wallpaper = wallpapers[index]
        WallpaperStore.shared.removeWallpaper(wallpaper)
        wallpapers.remove(at: index)
        WallpaperStore.shared.saveWallpapers(wallpapers)
        print("✓ Removed: \(wallpaper.displayName)")
    }
}

// MARK: - List Command
struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List wallpapers in the library"
    )

    @Flag(name: .shortAndLong, help: "Show detailed information")
    var verbose = false

    func run() throws {
        let wallpapers = WallpaperStore.shared.loadWallpapers()

        if wallpapers.isEmpty {
            print("No wallpapers in library")
            print("Add wallpapers with: armada add <path>")
            return
        }

        print("Library (\(wallpapers.count) wallpapers):\n")

        for (index, wallpaper) in wallpapers.enumerated() {
            let typeIcon = wallpaper.type == .gif ? "◉" : "▶"
            print("  \(index + 1). \(typeIcon) \(wallpaper.displayName).\(wallpaper.fileExtension)")

            if verbose {
                print("     ID: \(wallpaper.id.uuidString.prefix(8))...")
                print("     Added: \(wallpaper.dateAdded.formatted())")
                print("")
            }
        }
    }
}

// MARK: - Status Command
struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show current wallpaper status"
    )

    func run() throws {
        let isRunning = DaemonManager.shared.isRunning
        let settings = WallpaperStore.shared.loadSettings()
        let wallpapers = WallpaperStore.shared.loadWallpapers()

        print("Armada Status")
        print("─────────────")
        print("Daemon: \(isRunning ? "● Running" : "○ Stopped")")
        print("Library: \(wallpapers.count) wallpaper(s)")

        if !settings.displayAssignments.isEmpty {
            print("\nActive Wallpapers:")
            for assignment in settings.displayAssignments {
                if let wallpaperID = assignment.wallpaperID,
                   let wallpaper = wallpapers.first(where: { $0.id == wallpaperID }) {
                    print("  Display \(assignment.displayID): \(wallpaper.displayName)")
                }
            }
        }

        if !isRunning {
            print("\nStart with: armada start")
        }
    }
}

// MARK: - Config Command
struct Config: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Configure wallpaper settings"
    )

    @Flag(name: .long, help: "Keep wallpaper playing even when other apps are in focus")
    var alwaysOn = false

    @Flag(name: .long, help: "Pause wallpaper when desktop is not visible (default behavior)")
    var autoPause = false

    @Flag(name: .long, help: "Resize video to fill the screen (default)")
    var autoResize = false

    @Flag(name: .long, help: "Keep original video size without resizing")
    var noResize = false

    func run() throws {
        let hasPlaybackFlags = alwaysOn || autoPause
        let hasResizeFlags = autoResize || noResize

        if !hasPlaybackFlags && !hasResizeFlags {
            // No flags specified, show current settings
            print("Config Options:")
            print("")
            print("  Playback:")
            print("    --always-on    Keep wallpaper playing when apps are in focus")
            print("    --auto-pause   Pause wallpaper when desktop is obscured (default)")
            print("")
            print("  Sizing:")
            print("    --auto-resize  Resize video to fill screen (default)")
            print("    --no-resize    Keep original video size")
            print("")
            print("Examples:")
            print("  armada config --always-on")
            print("  armada config --no-resize")
            print("  armada config --always-on --no-resize")
            return
        }

        if alwaysOn && autoPause {
            throw ValidationError("Cannot use both --always-on and --auto-pause")
        }

        if autoResize && noResize {
            throw ValidationError("Cannot use both --auto-resize and --no-resize")
        }

        // Ensure daemon is running
        if !DaemonManager.shared.isRunning {
            try DaemonManager.shared.start()
        }

        // Handle playback settings
        if hasPlaybackFlags {
            let playbackEnabled = alwaysOn
            try DaemonManager.shared.sendCommand(.setAlwaysOn(playbackEnabled))

            if playbackEnabled {
                print("✓ Always-on mode enabled - wallpaper will keep playing")
            } else {
                print("✓ Auto-pause mode enabled - wallpaper pauses when desktop is hidden")
            }
        }

        // Handle resize settings
        if hasResizeFlags {
            let resizeEnabled = autoResize
            try DaemonManager.shared.sendCommand(.setAutoResize(resizeEnabled))

            if resizeEnabled {
                print("✓ Auto-resize enabled - video fills the screen")
            } else {
                print("✓ Auto-resize disabled - video keeps original size")
            }
        }
    }
}
