cask "notch-so-good" do
  version "4.1.0"
  sha256 "b071e4874fe45e59a60bbd19e6b2331eabc94ad891d8025a5b504b36735a586f"

  url "https://github.com/deepshal99/notch-so-good/releases/download/v#{version}/NotchSoGood-#{version}.zip"
  name "Notch So Good"
  desc "Pixel-art crab in your notch that watches Claude Code, Codex, and Gemini sessions"
  homepage "https://github.com/deepshal99/notch-so-good"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

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
