cask "scroblebler" do
  version "1.1.1"
  sha256 "39ec5288a5229ee65cc8f775fa20362a8f7980c9d7c664f5fd8b77a9c87fd63d"

  url "https://github.com/tonioriol/scroblebler/releases/download/v#{version}/Scroblebler.1.0.2.dmg"
  name "Scroblebler"
  desc "Last.fm scrobbler for macOS Music app"
  homepage "https://github.com/tonioriol/scroblebler"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Scroblebler.app"

  zap trash: [
    "~/Library/Preferences/com.tonioriol.Scroblebler.plist",
    "~/Library/Application Support/Scroblebler",
  ]
end
