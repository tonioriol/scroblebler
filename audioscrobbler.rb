cask "audioscrobbler" do
  version "1.3"
  sha256 "519ec5c9bc583516ed4d86d51cdd7f4eba6d206e93d49d9d028b7d081fca6626"

  url "https://github.com/heyvito/audioscrobbler/releases/download/v#{version}/Audioscrobbler.#{version}.dmg"
  name "Audioscrobbler"
  desc "Last.fm scrobbler for macOS Music app"
  homepage "https://github.com/heyvito/audioscrobbler"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Audioscrobbler.app"

  zap trash: [
    "~/Library/Preferences/dev.vito.Audioscrobbler.plist",
    "~/Library/Application Support/Audioscrobbler",
  ]
end
