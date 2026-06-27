cask "redtick" do
  version "1.7.0"
  sha256 "6f7533fe3ae1d1e679b6eef5dcbb473b88033eb9c943e37b7b9f36cd4a506d0f"

  url "https://github.com/syky27/redtick/releases/download/v#{version}/redtick-v#{version}.dmg"
  name "Redtick"
  desc "Redmine-native time tracker (Toggl Desktop experience for Redmine)"
  homepage "https://github.com/syky27/redtick"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates false
  depends_on macos: :catalina
  depends_on arch: :arm64

  app "redtick.app"

  zap trash: [
    "~/Library/Application Support/cz.syky.redtick.redtick",
    "~/Library/Caches/cz.syky.redtick.redtick",
    "~/Library/HTTPStorages/cz.syky.redtick.redtick",
    "~/Library/Preferences/cz.syky.redtick.redtick.plist",
    "~/Library/Saved Application State/cz.syky.redtick.redtick.savedState",
  ]
end
