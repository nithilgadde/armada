import Foundation
import AppKit
import AVFoundation

// MARK: - Desktop Window Manager
/// Manages wallpaper windows across all displays
/// Creates borderless windows positioned below desktop icons
final class DesktopWindowManager {
    static let shared = DesktopWindowManager()

    /// Currently active wallpaper windows keyed by display ID
    private(set) var activeWindows: [String: WallpaperWindow] = [:]

    /// Whether playback is currently paused due to desktop not being visible
    private(set) var isPaused: Bool = false

    /// When true, wallpaper keeps playing even when desktop is obscured
    var alwaysOn: Bool = false

    /// When true, video is resized to fill the screen (default). When false, original size is maintained.
    var autoResize: Bool = true

    private var displayObserver: Any?
    private var spaceObserver: Any?
    private var appObserver: Any?
    private var sleepObserver: Any?
    private var wakeObserver: Any?

    // Track desktop visibility
    private var desktopVisibilityTimer: Timer?

    private init() {
        setupObservers()
    }

    deinit {
        removeObservers()
        closeAllWindows()
    }

    // MARK: - Public Methods

    /// Sets up a wallpaper for a specific display
    /// - Parameters:
    ///   - wallpaper: The wallpaper to display
    ///   - screen: The target screen (defaults to main screen)
    func setWallpaper(_ wallpaper: Wallpaper, for screen: NSScreen? = nil) {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!
        let displayID = displayID(for: targetScreen)

        // Close existing window for this display
        activeWindows[displayID]?.close()

        // Create new wallpaper window
        let window = WallpaperWindow(wallpaper: wallpaper, screen: targetScreen)
        activeWindows[displayID] = window

        // Apply current pause state
        if isPaused {
            window.pause()
        } else {
            window.play()
        }
    }

    /// Sets wallpaper for all displays
    func setWallpaperForAllDisplays(_ wallpaper: Wallpaper) {
        for screen in NSScreen.screens {
            setWallpaper(wallpaper, for: screen)
        }
    }

    /// Removes wallpaper from a specific display
    func removeWallpaper(for screen: NSScreen? = nil) {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!
        let displayID = displayID(for: targetScreen)

        activeWindows[displayID]?.close()
        activeWindows.removeValue(forKey: displayID)
    }

    /// Removes wallpapers from all displays
    func removeAllWallpapers() {
        closeAllWindows()
    }

    /// Pauses all wallpaper playback
    func pauseAll() {
        isPaused = true
        activeWindows.values.forEach { $0.pause() }
    }

    /// Resumes all wallpaper playback
    func resumeAll() {
        isPaused = false
        activeWindows.values.forEach { $0.play() }
    }

    /// Updates video gravity (resize mode) for all windows
    func updateVideoGravity() {
        activeWindows.values.forEach { $0.updateVideoGravity(autoResize: autoResize) }
    }

    /// Gets the display ID for a screen
    func displayID(for screen: NSScreen) -> String {
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        return String(screenNumber)
    }

    /// Updates windows when screen configuration changes
    func handleScreenChange() {
        let currentScreenIDs = Swift.Set(NSScreen.screens.map { displayID(for: $0) })
        let existingIDs = Swift.Set(activeWindows.keys)

        // Remove windows for disconnected displays
        for id in existingIDs.subtracting(currentScreenIDs) {
            activeWindows[id]?.close()
            activeWindows.removeValue(forKey: id)
        }

        // Reposition existing windows
        for screen in NSScreen.screens {
            let id = displayID(for: screen)
            activeWindows[id]?.updateFrame(for: screen)
        }
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // Screen configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Space changes (Mission Control)
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkDesktopVisibility()
        }

        // App activation changes
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkDesktopVisibility()
        }

        // Sleep notification
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pauseAll()
        }

        // Wake notification
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delay to allow system to fully wake
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.handleWake()
            }
        }

        // Start visibility monitoring timer
        startVisibilityMonitoring()
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)

        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }

        desktopVisibilityTimer?.invalidate()
    }

    @objc private func screenDidChange() {
        handleScreenChange()
    }

    /// Handles system wake from sleep
    private func handleWake() {
        // Force resume all existing wallpapers (handles stuck players after sleep)
        isPaused = false
        for window in activeWindows.values {
            window.forceResume()
        }

        // Check if we need to handle visibility (auto-pause if desktop not visible)
        if !alwaysOn {
            checkDesktopVisibility()
        }
    }

    /// Starts periodic monitoring of desktop visibility
    private func startVisibilityMonitoring() {
        desktopVisibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkDesktopVisibility()
        }
    }

    /// Checks if the desktop is currently visible and pauses/resumes accordingly
    private func checkDesktopVisibility() {
        // Skip visibility checking if always-on mode is enabled
        if alwaysOn {
            if isPaused {
                resumeAll()
            }
            return
        }

        let isDesktopVisible = isDesktopCurrentlyVisible()

        if isDesktopVisible && isPaused {
            resumeAll()
        } else if !isDesktopVisible && !isPaused {
            pauseAll()
        }
    }

    /// Determines if the desktop is currently visible to the user
    private func isDesktopCurrentlyVisible() -> Bool {
        // Check if any fullscreen app is active
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            // If Finder is frontmost, desktop is likely visible
            if frontApp.bundleIdentifier == "com.apple.finder" {
                return true
            }

            // Check if any window is covering the entire screen
            let options = CGWindowListOption.optionOnScreenOnly
            guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
                return true
            }

            for window in windowList {
                guard let layer = window[kCGWindowLayer as String] as? Int,
                      let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else {
                    continue
                }

                // Skip our own wallpaper windows and desktop-level windows
                if layer <= CGWindowLevelForKey(.desktopWindow) {
                    continue
                }

                // Check if this window covers a significant portion of any screen
                let windowFrame = CGRect(
                    x: bounds["X"] ?? 0,
                    y: bounds["Y"] ?? 0,
                    width: bounds["Width"] ?? 0,
                    height: bounds["Height"] ?? 0
                )

                for screen in NSScreen.screens {
                    let screenFrame = screen.frame
                    let intersection = windowFrame.intersection(screenFrame)
                    let coverage = (intersection.width * intersection.height) / (screenFrame.width * screenFrame.height)

                    // If a window covers more than 90% of a screen, consider desktop not visible
                    if coverage > 0.9 {
                        return false
                    }
                }
            }
        }

        return true
    }

    private func closeAllWindows() {
        activeWindows.values.forEach { $0.close() }
        activeWindows.removeAll()
    }
}

// MARK: - Wallpaper Window
/// A borderless window that displays wallpaper content at the desktop level
final class WallpaperWindow: NSWindow {
    private var wallpaper: Wallpaper
    private var wallpaperViewController: WallpaperContentViewController?

    init(wallpaper: Wallpaper, screen: NSScreen) {
        self.wallpaper = wallpaper

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        setFrameOrigin(screen.frame.origin)
        setupWindow()
        setupContent()
    }

    private func setupWindow() {
        // Window configuration for desktop-level display
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.isOpaque = true
        self.hasShadow = false
        self.backgroundColor = .black
        self.ignoresMouseEvents = true
        self.isReleasedWhenClosed = false

        // Make window appear on all spaces
        self.collectionBehavior.insert(.canJoinAllSpaces)

        self.orderBack(nil)
        self.makeKeyAndOrderFront(nil)
    }

    private func setupContent() {
        let viewController = WallpaperContentViewController(wallpaper: wallpaper)
        self.wallpaperViewController = viewController
        self.contentView = viewController.view
    }

    /// Updates the window frame for a new screen configuration
    func updateFrame(for screen: NSScreen) {
        self.setFrame(screen.frame, display: true)
    }

    /// Pauses wallpaper playback
    func pause() {
        wallpaperViewController?.pause()
    }

    /// Resumes wallpaper playback
    func play() {
        wallpaperViewController?.play()
    }

    /// Force resume after system wake
    func forceResume() {
        wallpaperViewController?.forceResume()
    }

    /// Updates video gravity (resize mode)
    func updateVideoGravity(autoResize: Bool) {
        wallpaperViewController?.updateVideoGravity(autoResize: autoResize)
    }

    override func close() {
        wallpaperViewController?.cleanup()
        super.close()
    }
}

// MARK: - Wallpaper Content View Controller
/// Manages the content view for displaying wallpaper (video or GIF)
final class WallpaperContentViewController: NSViewController {
    private let wallpaper: Wallpaper
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerLooper: AVPlayerLooper?
    private var gifRenderer: GIFRenderer?
    private var gifLayer: CALayer?
    private var playerObserver: Any?

    init(wallpaper: Wallpaper) {
        self.wallpaper = wallpaper
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContent()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        playerLayer?.frame = view.bounds
        gifLayer?.frame = view.bounds
    }

    private func setupContent() {
        let fileURL = WallpaperStore.shared.localURL(for: wallpaper)

        switch wallpaper.type {
        case .mp4:
            setupVideoPlayer(url: fileURL)
        case .gif:
            setupGIFRenderer(url: fileURL)
        case .unknown:
            break
        }
    }

    private func setupVideoPlayer(url: URL) {
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        // Use AVQueuePlayer for seamless looping
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true // Mute by default for wallpapers

        // Create looper for seamless video looping
        playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)

        self.player = queuePlayer

        // Setup player layer
        let layer = AVPlayerLayer(player: queuePlayer)
        layer.videoGravity = DesktopWindowManager.shared.autoResize ? .resizeAspectFill : .resizeAspect
        layer.frame = view.bounds

        view.layer?.addSublayer(layer)
        self.playerLayer = layer

        queuePlayer.play()
    }

    private func setupGIFRenderer(url: URL) {
        guard let renderer = GIFRenderer(url: url) else {
            return
        }
        self.gifRenderer = renderer

        let layer = CALayer()
        layer.frame = view.bounds
        layer.contentsGravity = DesktopWindowManager.shared.autoResize ? .resizeAspectFill : .resizeAspect

        view.layer?.addSublayer(layer)
        self.gifLayer = layer

        renderer.start { [weak self] image in
            DispatchQueue.main.async {
                self?.gifLayer?.contents = image
            }
        }
    }

    func pause() {
        player?.pause()
        gifRenderer?.pause()
    }

    func play() {
        player?.play()
        gifRenderer?.resume()
    }

    /// Force resume playback after system wake - handles stuck players
    func forceResume() {
        // For video: seek to current time to kick the player back into action
        if let player = player {
            let currentTime = player.currentTime()
            player.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                self?.player?.play()
            }
        }

        // For GIF: reset timing and resume
        gifRenderer?.resetTimingAndResume()
    }

    func updateVideoGravity(autoResize: Bool) {
        let gravity: CALayerContentsGravity = autoResize ? .resizeAspectFill : .resizeAspect
        let videoGravity: AVLayerVideoGravity = autoResize ? .resizeAspectFill : .resizeAspect

        playerLayer?.videoGravity = videoGravity
        gifLayer?.contentsGravity = gravity
    }

    func cleanup() {
        player?.pause()
        playerLooper?.disableLooping()
        playerLooper = nil
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil

        gifRenderer?.stop()
        gifRenderer = nil
        gifLayer?.removeFromSuperlayer()
        gifLayer = nil

        if let observer = playerObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
