cask "notch-so-good" do
  version "4.10.0"
  sha256 "d96ee13c91a8e1888b8c638bb22c61731ec0e11fa84e36f3544dde9c8e4bf8b1"

  url "https://github.com/deepshal99/notch-so-good/releases/download/v#{version}/NotchSoGood-#{version}.zip"
  name "Notch So Good"
  desc "Tiny 3D coworker in your notch that watches Claude Code and Codex CLI sessions"
  homepage "https://notchsogood.com"

  livecheck do
    url :url
    strategy :github_latest
  end

  # It updates itself (Sparkle); brew upgrade still works.
  auto_updates true
  depends_on macos: :sonoma

  app "NotchSoGood.app"

  # Not notarized (no Apple Developer account): clear the download flag so
  # Gatekeeper opens it without the "unidentified developer" detour.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/NotchSoGood.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Preferences/com.notchsogood.app.plist",
    "~/Library/Caches/com.notchsogood.app",
  ]

  caveats <<~EOS
    Launch the app once and it installs the Claude Code / Codex CLI hooks for
    you. To reinstall them later: menu bar icon -> Settings -> Reinstall hooks.

    For notifications to land on the display you're working on, and to focus the
    exact terminal window, grant Accessibility access when prompted.
  EOS
end
