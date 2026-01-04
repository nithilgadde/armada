class Armada < Formula
  desc "Native macOS live wallpaper manager - set videos and GIFs as desktop wallpaper"
  homepage "https://github.com/nithilgadde/armada"
  url "https://github.com/nithilgadde/armada/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "MIT"
  head "https://github.com/nithilgadde/armada.git", branch: "master"

  depends_on :macos
  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build",
           "--disable-sandbox",
           "--configuration", "release",
           "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../lib"
    bin.install ".build/release/armada"
  end

  def caveats
    <<~EOS
      To start using Armada:

        # Set a wallpaper
        armada set ~/path/to/video.mp4

        # Start the daemon manually
        armada start

        # Check status
        armada status

      For the daemon to start automatically at login, add this to your shell profile:
        armada start

      Or create a LaunchAgent (see documentation).
    EOS
  end

  test do
    assert_match "armada", shell_output("#{bin}/armada --help")
  end
end
