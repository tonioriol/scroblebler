cask "scroblebler" do
  version "0.2.0"
  sha256 "08276f506427832d38b22f026ab3c4301879b9be482b9151ed7d72a54f1824c6"

  url "https://github.com/tonioriol/scroblebler/releases/download/v#{version}/Scroblebler.#{version}.dmg"
  name "Scroblebler"
  desc "Last.fm scrobbler for macOS Music app"
  homepage "https://github.com/tonioriol/scroblebler"

  livecheck do
    url :homepage
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
