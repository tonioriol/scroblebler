cask "scroblebler" do
  version "1.3"
  sha256 "519ec5c9bc583516ed4d86d51cdd7f4eba6d206e93d49d9d028b7d081fca6626"

  url "https://github.com/tonioriol/scroblebler/releases/download/v#{version}/Scroblebler.#{version}.dmg"
  name "Scroblebler"
  desc "Last.fm scrobbler for macOS Music app"
  homepage "https://github.com/tonioriol/scroblebler"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Scroblebler.app"

  zap trash: [
    "~/Library/Preferences/dev.vito.Scroblebler.plist",
    "~/Library/Application Support/Scroblebler",
  ]
end
