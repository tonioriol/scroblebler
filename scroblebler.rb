cask "scroblebler" do
  version "0.1.0"
  sha256 "6edb1a902123409044117108dd60a7b41b1f0eb62257fbf4feaa73db0bc492a6"

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
