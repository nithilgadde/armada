import Foundation
import AppKit
import ImageIO

// MARK: - GIF Renderer
/// Renders animated GIFs using ImageIO framework for efficient frame extraction
/// Handles proper frame timing and seamless looping
final class GIFRenderer {
    private let imageSource: CGImageSource
    private let frameCount: Int
    private var frames: [CGImage] = []
    private var frameDurations: [TimeInterval] = []
    private var currentFrameIndex: Int = 0
    private var displayLink: CVDisplayLink?
    private var lastFrameTime: CFTimeInterval = 0
    private var accumulatedTime: CFTimeInterval = 0
    private var frameCallback: ((CGImage) -> Void)?
    private var isPaused: Bool = false
    private var isRunning: Bool = false

    /// Total duration of one complete GIF loop
    private(set) var totalDuration: TimeInterval = 0

    /// Initializes the renderer with a GIF file URL
    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        self.imageSource = source
        self.frameCount = CGImageSourceGetCount(source)

        guard frameCount > 0 else { return nil }

        loadFrames()
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// Starts the GIF animation with a callback for each frame
    /// - Parameter callback: Called with each frame's CGImage
    func start(callback: @escaping (CGImage) -> Void) {
        guard !isRunning, !frames.isEmpty else { return }

        self.frameCallback = callback
        self.isRunning = true
        self.isPaused = false

        // Deliver first frame immediately
        callback(frames[0])

        setupDisplayLink()
    }

    /// Stops the GIF animation
    func stop() {
        isRunning = false
        stopDisplayLink()
        frameCallback = nil
    }

    /// Pauses the animation
    func pause() {
        isPaused = true
    }

    /// Resumes the animation
    func resume() {
        isPaused = false
    }

    /// Resets timing and resumes - use after system wake to avoid timing jumps
    func resetTimingAndResume() {
        lastFrameTime = CACurrentMediaTime()
        accumulatedTime = 0
        isPaused = false
    }

    /// Gets a specific frame
    func frame(at index: Int) -> CGImage? {
        guard index >= 0 && index < frames.count else { return nil }
        return frames[index]
    }

    /// Gets the first frame (useful for thumbnails)
    var firstFrame: CGImage? {
        frames.first
    }

    // MARK: - Private Methods

    /// Loads all frames and their durations from the GIF
    private func loadFrames() {
        for i in 0..<frameCount {
            guard let image = CGImageSourceCreateImageAtIndex(imageSource, i, nil) else {
                continue
            }

            frames.append(image)

            // Get frame duration from GIF properties
            let duration = frameDuration(at: i)
            frameDurations.append(duration)
            totalDuration += duration
        }
    }

    /// Extracts the frame duration for a specific frame index
    private func frameDuration(at index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [String: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] else {
            return 0.1 // Default to 100ms
        }

        // Try to get unclamped delay time first, then delay time
        var duration: TimeInterval = 0.1

        if let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double,
           unclampedDelay > 0 {
            duration = unclampedDelay
        } else if let delay = gifProperties[kCGImagePropertyGIFDelayTime as String] as? Double,
                  delay > 0 {
            duration = delay
        }

        // GIF spec: delays less than 10ms should be treated as 100ms
        if duration < 0.01 {
            duration = 0.1
        }

        return duration
    }

    /// Sets up CVDisplayLink for frame timing
    private func setupDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)

        guard let displayLink = link else { return }

        self.displayLink = displayLink
        lastFrameTime = CACurrentMediaTime()
        accumulatedTime = 0

        // Set up callback
        let callback: CVDisplayLinkOutputCallback = { displayLink, inNow, inOutputTime, flagsIn, flagsOut, context in
            guard let context = context else { return kCVReturnError }

            let renderer = Unmanaged<GIFRenderer>.fromOpaque(context).takeUnretainedValue()
            renderer.displayLinkCallback()

            return kCVReturnSuccess
        }

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, callback, pointer)
        CVDisplayLinkStart(displayLink)
    }

    /// Stops and releases the display link
    private func stopDisplayLink() {
        guard let link = displayLink else { return }
        CVDisplayLinkStop(link)
        displayLink = nil
    }

    /// Called by CVDisplayLink for each display refresh
    private func displayLinkCallback() {
        guard isRunning, !isPaused, !frames.isEmpty else { return }

        let currentTime = CACurrentMediaTime()
        let deltaTime = currentTime - lastFrameTime
        lastFrameTime = currentTime

        accumulatedTime += deltaTime

        // Check if we should advance to the next frame
        let currentFrameDuration = frameDurations[currentFrameIndex]

        if accumulatedTime >= currentFrameDuration {
            accumulatedTime -= currentFrameDuration

            // Advance to next frame (loop back to 0 at the end)
            currentFrameIndex = (currentFrameIndex + 1) % frameCount

            // Deliver the frame on main thread
            let frame = frames[currentFrameIndex]
            DispatchQueue.main.async { [weak self] in
                self?.frameCallback?(frame)
            }
        }
    }
}

// MARK: - GIF Thumbnail Generator
/// Utility for generating static thumbnails from GIF files
struct GIFThumbnailGenerator {
    /// Generates a thumbnail image from a GIF file
    /// - Parameters:
    ///   - url: URL of the GIF file
    ///   - maxSize: Maximum dimension for the thumbnail
    /// - Returns: NSImage thumbnail or nil if generation fails
    static func generateThumbnail(from url: URL, maxSize: CGFloat = 200) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }
}

