# Armada: a FREE macos live wallpaper app

A native macOS command-line tool to set animated videos and GIFs as your desktop wallpaper.

## Installation

# XCODE APPLICATION IS REQUIRED FOR ALL BUILDS!

### Homebrew (Recommended)

```bash
brew tap nithilgadde/tap
brew install armada
```

### Build from Source

Requires Xcode 15+ or Swift 5.9+ toolchain.

```bash
git clone https://github.com/nithilgadde/armada.git
cd armada
swift build -c release
sudo cp .build/release/armada /usr/local/bin/
```

## Usage

```bash
# Set a video as wallpaper (starts daemon automatically)
armada set ~/Videos/cool-animation.mp4

# Set a GIF as wallpaper
armada set ~/Pictures/animated.gif

# Set wallpaper for a specific display
armada set ~/Videos/video.mp4 --display 2

# Set for all displays
armada set ~/Videos/video.mp4 --display all

# Remove wallpaper
armada unset
armada unset --display 1

# Check status
armada status

# Manage the daemon
armada start
armada stop

# Library management
armada add ~/Videos/new-wallpaper.mp4
armada list
armada list --verbose
armada remove "wallpaper-name"
```

## Commands

| Command | Description |
|---------|-------------|
| `set <path>` | Set a video/GIF as wallpaper |
| `unset` | Remove wallpaper from display(s) |
| `start` | Start the wallpaper daemon |
| `stop` | Stop the daemon and remove all wallpapers |
| `status` | Show current wallpaper status |
| `add <path>` | Add wallpaper to library |
| `list` | List wallpapers in library |
| `remove <name>` | Remove wallpaper from library |

## Options

```
-d, --display <n|all>  Target display (default: all)
-f, --foreground       Run daemon in foreground
-v, --verbose          Show detailed information
-h, --help             Show help
--version              Show version
```

## Supported Formats

- **Video**: MP4, M4V, MOV
- **Image**: GIF (animated)

## How It Works

Armada creates a borderless window positioned at the desktop level (behind your icons) and plays your video/GIF in a loop. The daemon automatically:

- **Pauses playback** when the desktop isn't visible (fullscreen apps, Mission Control)
- **Resumes playback** when you return to the desktop
- **Handles sleep/wake** cycles gracefully
- **Supports multiple displays** with independent wallpapers

## Auto-Start at Login

### Option 1: Shell Profile

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
armada start 2>/dev/null &
```

### Option 2: LaunchAgent

Create `~/Library/LaunchAgents/com.armada.agent.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.armada.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/armada</string>
        <string>start</string>
        <string>--foreground</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

Then load it:

```bash
launchctl load ~/Library/LaunchAgents/com.armada.agent.plist
```

## Data Storage

Wallpapers and settings are stored in:
```
~/Library/Application Support/Armada/
├── Wallpapers/          # Imported wallpaper files
├── wallpapers.json      # Library metadata
├── settings.json        # App settings
├── daemon.sock          # Unix socket for IPC
└── daemon.pid           # Daemon process ID
```

## Architecture

```
┌─────────────────┐     Unix Socket     ┌─────────────────┐
│   CLI Command   │ ──────────────────▶ │     Daemon      │
│    (armada)     │                     │  (background)   │
└─────────────────┘                     └────────┬────────┘
                                                 │
                                    ┌────────────┴────────────┐
                                    │                         │
                              ┌─────▼─────┐            ┌─────▼─────┐
                              │ Display 1 │            │ Display 2 │
                              │  Window   │            │  Window   │
                              └───────────┘            └───────────┘
```

## Performance

- Uses **AVPlayerLooper** for gapless video looping with hardware decoding
- Uses **CVDisplayLink** for vsync'd GIF animation
- Automatically pauses when desktop is obscured to save CPU/GPU
- Minimal memory footprint (streams from disk)

## Requirements

- macOS 13.0 (Ventura) or later
- For building: Xcode 15+ or Swift 5.9+

## Troubleshooting

### Wallpaper not visible

Make sure you're viewing the desktop (not a fullscreen app):
```bash
armada status
```

### Daemon won't start

Check if another instance is running:
```bash
ps aux | grep armada
armada stop
armada start
```

### Permission issues

The app needs permission to access your files. Grant access when prompted, or add Terminal/your shell to System Preferences → Privacy & Security → Files and Folders.

## License

MIT License

## Contributing

Issues and pull requests welcome at https://github.com/nithilgadde/armada
