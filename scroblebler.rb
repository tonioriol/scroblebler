cask "scroblebler" do
  version "1.0.2"
  sha256 "46d381441d5fe9f9bfd3e0fa088d7d32d23668461120951fd7bf8418dd9fe760"

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
