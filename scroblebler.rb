cask "scroblebler" do
  version "1.2.0"
  sha256 "02a79e6dd37dab6356b387390a0c238b7054699d7adb403a91e468ba2b792c11"

  url "https://github.com/tonioriol/scroblebler/releases/download/v#{version}/Scroblebler.1.0.2.dmg"
  name "Scroblebler"
  desc "Last.fm scrobbler for macOS Music app"
  homepage "https://github.com/tonioriol/scroblebler"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Scroblebler.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/Scroblebler.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Preferences/com.tonioriol.Scroblebler.plist",
    "~/Library/Application Support/Scroblebler",
  ]
end
