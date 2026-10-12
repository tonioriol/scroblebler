cask "scroblebler" do
  version "1.2.0"
  sha256 "4f1583750cbd760094c86b24c5469d5339d6dc94171567a0cf91b0179f86e81d"

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
