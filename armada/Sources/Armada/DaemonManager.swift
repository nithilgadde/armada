import Foundation
import AppKit

// MARK: - Daemon Command
enum DaemonCommand: Codable {
    case setWallpaper(path: String, display: String)
    case unsetWallpaper(display: String)
    case setAlwaysOn(Bool)
    case setAutoResize(Bool)
    case pause
    case resume
    case quit
}

// MARK: - Daemon Manager
/// Manages the background wallpaper daemon process
final class DaemonManager {
    static let shared = DaemonManager()

    private let socketPath: String
    private let pidFile: String
    private var server: DaemonServer?

    private init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Armada", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

        self.socketPath = supportDir.appendingPathComponent("daemon.sock").path
        self.pidFile = supportDir.appendingPathComponent("daemon.pid").path
    }

    /// Check if daemon is currently running
    var isRunning: Bool {
        guard let pidString = try? String(contentsOfFile: pidFile, encoding: .utf8),
              let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }

        // Check if process exists
        return kill(pid, 0) == 0
    }

    /// Start the daemon process
    func start() throws {
        if isRunning {
            return // Already running
        }

        // Get path to current executable - resolve symlinks and get absolute path
        let arg0 = CommandLine.arguments[0]
        let executablePath: String
        if arg0.hasPrefix("/") {
            executablePath = arg0
        } else if let resolvedPath = ProcessInfo.processInfo.arguments.first,
                  resolvedPath.hasPrefix("/") {
            executablePath = resolvedPath
        } else {
            // Fall back to searching PATH
            let whichProcess = Process()
            whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            whichProcess.arguments = ["armada"]
            let pipe = Pipe()
            whichProcess.standardOutput = pipe
            try? whichProcess.run()
            whichProcess.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            executablePath = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "/opt/homebrew/bin/armada"
        }

        // Launch daemon process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["start", "--foreground"]

        // Detach from terminal
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()

        // Wait briefly for daemon to start
        Thread.sleep(forTimeInterval: 0.5)

        // Verify it started
        if !isRunning {
            throw DaemonError.failedToStart
        }
    }

    /// Stop the daemon process
    func stop() throws {
        guard let pidString = try? String(contentsOfFile: pidFile, encoding: .utf8),
              let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return // Not running
        }

        // Try graceful shutdown first
        do {
            try sendCommand(.quit)
            Thread.sleep(forTimeInterval: 0.5)
        } catch {
            // Fall back to SIGTERM
            kill(pid, SIGTERM)
        }

        // Clean up files
        try? FileManager.default.removeItem(atPath: pidFile)
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    /// Send a command to the running daemon
    func sendCommand(_ command: DaemonCommand) throws {
        guard isRunning else {
            throw DaemonError.notRunning
        }

        // Connect to Unix socket
        let socket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw DaemonError.socketError
        }
        defer { close(socket) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dest in
                _ = strcpy(dest, ptr)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(socket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            throw DaemonError.connectionFailed
        }

        // Send command
        let data = try JSONEncoder().encode(command)
        let message = data + Data([0]) // Null-terminated

        _ = message.withUnsafeBytes { ptr in
            send(socket, ptr.baseAddress, message.count, 0)
        }
    }

    /// Run the daemon in foreground (blocking)
    func runInForeground() {
        // Write PID file
        try? "\(getpid())".write(toFile: pidFile, atomically: true, encoding: .utf8)

        // Set up signal handlers
        signal(SIGTERM) { _ in
            DaemonManager.shared.cleanup()
            exit(0)
        }

        signal(SIGINT) { _ in
            DaemonManager.shared.cleanup()
            exit(0)
        }

        // Start command server
        server = DaemonServer(socketPath: socketPath)
        server?.start()

        // Run the NSApplication
        let app = NSApplication.shared
        let delegate = WallpaperDaemonDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // Hide from Dock
        app.run()
    }

    private func cleanup() {
        DesktopWindowManager.shared.removeAllWallpapers()
        try? FileManager.default.removeItem(atPath: pidFile)
        try? FileManager.default.removeItem(atPath: socketPath)
    }
}

// MARK: - Daemon Errors
enum DaemonError: LocalizedError {
    case failedToStart
    case notRunning
    case socketError
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .failedToStart: return "Failed to start daemon"
        case .notRunning: return "Daemon is not running"
        case .socketError: return "Socket error"
        case .connectionFailed: return "Failed to connect to daemon"
        }
    }
}

// MARK: - Daemon Server
/// Unix socket server for receiving commands
final class DaemonServer {
    private let socketPath: String
    private var serverSocket: Int32 = -1
    private var isRunning = false

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func start() {
        // Remove existing socket
        unlink(socketPath)

        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dest in
                _ = strcpy(dest, ptr)
            }
        }

        // Bind
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else { return }

        // Listen
        guard listen(serverSocket, 5) == 0 else { return }

        isRunning = true

        // Accept connections in background
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.acceptLoop()
        }
    }

    private func acceptLoop() {
        while isRunning {
            let clientSocket = accept(serverSocket, nil, nil)
            guard clientSocket >= 0 else { continue }

            // Read command
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = recv(clientSocket, &buffer, buffer.count, 0)
            close(clientSocket)

            guard bytesRead > 0 else { continue }

            // Parse and execute command
            let data = Data(buffer[0..<bytesRead])
            if let nullIndex = data.firstIndex(of: 0) {
                let commandData = data[0..<nullIndex]
                if let command = try? JSONDecoder().decode(DaemonCommand.self, from: commandData) {
                    DispatchQueue.main.async {
                        self.executeCommand(command)
                    }
                }
            }
        }
    }

    private func executeCommand(_ command: DaemonCommand) {
        switch command {
        case .setWallpaper(let path, let display):
            setWallpaper(path: path, display: display)

        case .unsetWallpaper(let display):
            unsetWallpaper(display: display)

        case .setAlwaysOn(let enabled):
            DesktopWindowManager.shared.alwaysOn = enabled
            if enabled {
                DesktopWindowManager.shared.resumeAll()
            }

        case .setAutoResize(let enabled):
            DesktopWindowManager.shared.autoResize = enabled
            DesktopWindowManager.shared.updateVideoGravity()

        case .pause:
            DesktopWindowManager.shared.pauseAll()

        case .resume:
            DesktopWindowManager.shared.resumeAll()

        case .quit:
            NSApplication.shared.terminate(nil)
        }
    }

    private func setWallpaper(path: String, display: String) {
        let url = URL(fileURLWithPath: path)

        // Import if not already in library
        var wallpaper: Wallpaper?
        let wallpapers = WallpaperStore.shared.loadWallpapers()

        // Check if already in library
        wallpaper = wallpapers.first { WallpaperStore.shared.localURL(for: $0).path == path }

        // Or import new
        if wallpaper == nil {
            if let imported = WallpaperStore.shared.importWallpaper(from: url) {
                var updatedWallpapers = wallpapers
                updatedWallpapers.append(imported)
                WallpaperStore.shared.saveWallpapers(updatedWallpapers)
                wallpaper = imported
            }
        }

        // Also check if the path matches the original URL
        if wallpaper == nil {
            wallpaper = wallpapers.first { $0.originalURL.path == path }
        }

        guard let wp = wallpaper else { return }

        // Set for display(s)
        let screens = NSScreen.screens

        if display == "all" {
            for screen in screens {
                DesktopWindowManager.shared.setWallpaper(wp, for: screen)
            }
        } else if let displayNum = Int(display), displayNum > 0, displayNum <= screens.count {
            DesktopWindowManager.shared.setWallpaper(wp, for: screens[displayNum - 1])
        }

        // Save settings
        var settings = WallpaperStore.shared.loadSettings()
        if display == "all" {
            for screen in screens {
                let displayID = DesktopWindowManager.shared.displayID(for: screen)
                settings.setWallpaper(wp.id, for: displayID)
            }
        } else if let displayNum = Int(display), displayNum > 0, displayNum <= screens.count {
            let displayID = DesktopWindowManager.shared.displayID(for: screens[displayNum - 1])
            settings.setWallpaper(wp.id, for: displayID)
        }
        settings.lastActiveWallpaperID = wp.id
        WallpaperStore.shared.saveSettings(settings)
    }

    private func unsetWallpaper(display: String) {
        let screens = NSScreen.screens

        if display == "all" {
            DesktopWindowManager.shared.removeAllWallpapers()
        } else if let displayNum = Int(display), displayNum > 0, displayNum <= screens.count {
            DesktopWindowManager.shared.removeWallpaper(for: screens[displayNum - 1])
        }
    }

    func stop() {
        isRunning = false
        close(serverSocket)
        unlink(socketPath)
    }
}

// MARK: - Wallpaper Daemon Delegate
final class WallpaperDaemonDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Restore previous wallpapers
        restoreWallpapers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DesktopWindowManager.shared.removeAllWallpapers()
    }

    private func restoreWallpapers() {
        let settings = WallpaperStore.shared.loadSettings()
        let wallpapers = WallpaperStore.shared.loadWallpapers()

        for screen in NSScreen.screens {
            let displayID = DesktopWindowManager.shared.displayID(for: screen)
            if let wallpaperID = settings.wallpaperID(for: displayID),
               let wallpaper = wallpapers.first(where: { $0.id == wallpaperID }) {
                DesktopWindowManager.shared.setWallpaper(wallpaper, for: screen)
            }
        }
    }
}
