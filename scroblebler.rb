cask "scroblebler" do
  version "1.2.1"
  sha256 "d43b6ab3fff3ec8c3553646906d6a0ef6f078c49e71976046ce0014787a43f11"

  url "https://github.com/tonioriol/scroblebler/releases/download/v#{version}/Scroblebler-v#{version}.zip"
  name "Scroblebler"
  desc "Last.fm scrobbler for macOS Music app"
  homepage "https://github.com/tonioriol/scroblebler"

  livecheck do
    url :homepage
    strategy :github_latest
  end

  depends_on macos: ">= :big_sur"

  app "Scroblebler.app"

  zap trash: [
    "~/Library/Preferences/com.tonioriol.Scroblebler.plist",
    "~/Library/Application Support/Scroblebler",
  ]
end
