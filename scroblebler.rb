cask "scroblebler" do
  version "1.4.0"
  sha256 "e2ae84579581342c4e71432ff4557128913a52767c03a5bbb21033d3f35423c2"

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
