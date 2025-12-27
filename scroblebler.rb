cask "scroblebler" do
  version "1.3.0"
  sha256 "6a57a376159954c91a5676dfe674930898e75ae7563f06f6c546f0f431256091"

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
