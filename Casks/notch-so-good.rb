cask "notch-so-good" do
  version "4.3.0"
  sha256 "600aa6490bcbf93588242cce63bb9b6e9de1425c7746fa0b5307f54a35309151"

  url "https://github.com/deepshal99/notch-so-good/releases/download/v#{version}/NotchSoGood-#{version}.zip"
  name "Notch So Good"
  desc "Pixel-art crab in your notch that watches Claude Code, Codex, and Gemini sessions"
  homepage "https://github.com/deepshal99/notch-so-good"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "NotchSoGood.app"

  # App is ad-hoc signed (not notarized) — clear quarantine so Gatekeeper lets it launch
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
    Launch the app once, then install the agent hooks from the menu bar
    (Reinstall Hooks) or run:
      bash HookInstaller/install-hooks.sh
  EOS
end
