cask "scrobblr" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/asharahmed/scrobblr/releases/download/v#{version}/Scrobblr.dmg"
  name "Scrobblr"
  desc "Last.fm scrobbler for Apple Music"
  homepage "https://github.com/asharahmed/scrobblr"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Sparkle updates the app itself, so Homebrew leaves upgrades to it.
  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Scrobblr.app"

  uninstall quit: "app.scrobblr.Scrobblr"

  zap trash: [
    "~/Library/Application Support/Scrobblr",
    "~/Library/Caches/app.scrobblr.Scrobblr",
    "~/Library/HTTPStorages/app.scrobblr.Scrobblr",
    "~/Library/Preferences/app.scrobblr.Scrobblr.plist",
    "~/Library/WebKit/app.scrobblr.Scrobblr",
  ]
end
