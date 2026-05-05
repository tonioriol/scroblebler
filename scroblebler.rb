cask "scroblebler" do
  version "1.0.0"
  sha256 "2c8e07c3ed31fbbc511e3fbafa894e77704885e3ac2bb28de52bbc20bb82677a"

  url "https://github.com/tonioriol/scroblebler/releases/download/v#{version}/Scroblebler-v#{version}.zip"
  name "Scroblebler"
  desc "Last.fm scrobbler for macOS Music app"
  homepage "https://github.com/tonioriol/scroblebler"

  livecheck do
    url :homepage
    strategy :github_latest
  end

  app "Scroblebler.app"

  zap trash: [
    "~/Library/Preferences/com.tonioriol.Scroblebler.plist",
    "~/Library/Application Support/Scroblebler",
  ]
end
