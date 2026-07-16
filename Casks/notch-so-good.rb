cask "notch-so-good" do
  version "4.1.1"
  sha256 "cd0254d4e3147e3f48de2379b9bc0e5fff1c81122918f02091f7501d248ceef5"

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
