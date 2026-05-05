# Scroblebler for Apple Music

<img src="imgs/logo.svg" height="64" align="right">

Scroblebler is a native macOS application that scrobbles tracks from any media player — Apple Music, Spotify, browsers, and more — using the system MediaRemote framework.

## Features

- **Universal Source Support**: Scrobbles from any media player via MediaRemote (Apple Music, Spotify, browsers, etc.)
- **Smart Music Detection**: Automatically filters out non-music content (YouTube videos, podcasts, tech talks) using the ListenBrainz MBID Mapper with a fallback chain (trusted players → cache → API → local DB → album heuristic → fail-closed)
- **Multiple Scrobbling Services**: Support for Last.fm, ListenBrainz, and Libre.fm
- **Unidirectional Sync**: Sync your listening history from a primary service to secondary services
- **Periodic Background Sync**: Automatically retries pending/failed operations every 60 seconds
- **Service-Specific Branding**: Visual indicators for each scrobbling service with logos and colors
- **Track Loving**: Love/unlove tracks directly from the app
- **Blacklist Management**: Blacklist tracks to prevent unwanted scrobbles
- **Undo Support**: Undo recent scrobbles with reliable web-based Last.fm deletion
- **Play Count Display**: View play counts for your tracks
- **Listening History**: Browse your full scrobble history with infinite scroll, offset-based pagination, and background backfill
- **Profile View**: View your scrobbling profile with avatar and statistics
- **Album Artwork**: Display album artwork with disk-persistent caching and Last.fm fallback
- **Now Playing**: Real-time now playing updates
- **Launch at Startup**: Automatically start scrobbling when you log in
- **Offline Queue**: Scrobbles are queued when offline and synced when connectivity returns
- **Fast Startup**: UI renders instantly — network calls happen in the background

## Screenshot

<img src="imgs/screenshot.png" width="600" />

## Installing

### Homebrew (Recommended)

```bash
brew install --cask tonioriol/scroblebler/scroblebler
```

### Manual

Download the latest DMG from [Releases](https://github.com/tonioriol/scroblebler/releases/latest) and drag Scroblebler to Applications.

After installation, remove quarantine attributes:
```bash
xattr -cr /Applications/Scroblebler.app
```

## Building

### Prerequisites

- Xcode 15.0+

### From Xcode

1. Clone this repository:
   ```bash
   git clone https://github.com/tonioriol/scroblebler.git
   cd scroblebler
   ```

2. Open `Scroblebler.xcodeproj` in Xcode

3. Xcode will automatically fetch the Swift package dependencies

4. Build the project (⌘B)

**Note**: On first build, you must configure the MediaRemoteAdapter framework embedding:
   - Select the Scroblebler target
   - Go to General tab
   - Under "Frameworks, Libraries, and Embedded Content"
   - Set MediaRemoteAdapter.framework to "Embed & Sign"

### Release Build

To create a release DMG:
```bash
./scripts/build.sh <version>
```

### Replace Homebrew Install with Dev Build

To run your local debug build instead of the Homebrew-installed release:

```bash
# Build
xcodebuild -project Scroblebler.xcodeproj -scheme Scroblebler -configuration Debug build 2>&1 | tail -5

# Unlink Homebrew version (keeps the cask so `brew upgrade` still works later)
brew unlink scroblebler 2>/dev/null

# Symlink debug build into /Applications
ln -sf ~/Library/Developer/Xcode/DerivedData/Scroblebler-*/Build/Products/Debug/Scroblebler.app /Applications/Scroblebler.app

# Launch
open /Applications/Scroblebler.app
```

To revert back to the Homebrew release:
```bash
rm /Applications/Scroblebler.app
brew reinstall --cask scroblebler
```

## Testing

Run the test suite:
```bash
xcodebuild -project Scroblebler.xcodeproj -scheme Scroblebler -configuration Debug test 2>&1 | tail -20
```


## Credits

This project is a fork of the original [Audioscrobbler](https://github.com/heyvito/audioscrobbler) by Victor Gama, with additional features.

Media playback control and detection uses [mediaremote-adapter](https://github.com/ejbills/mediaremote-adapter) by ejbills (forked from ungive's original work), which provides a Swift interface to macOS's private MediaRemote framework.

## Oh no, you pushed your token and secret!

Yep. I know! There's not much one can do with the API, and even Last.fm's tokens are [available
on their repository](https://github.com/lastfm/lastfm-desktop/blob/9ae84cf4ab204a92e6953abe14026df70c140519/lib/unicorn/UnicornCoreApplication.cpp#L58)

## Known Issues

- Music.app may restart immediately after quiting. I intend to fix this in the near future.

## TODO

- [x] Sign, Notarize & Provide DMG installer.
- [x] Start at Login.
- [x] Extract and unify the exponential backoff logic.
- [x] Add playcontrols.
- [x] Use proper logger.
- [x] Testing.
- [x] Links in now playing for lastfm not working.
- [x] Display full date on hover.
- [x] Detect non music playback (from browser, podcasts, videos, system sounds) — MusicValidator with MBID Mapper.
- [x] Filter out YouTube / non-music browser content — MusicValidator fail-closed for untrusted sources.
- [x] Local-first storage + sync engine (store scrobbles locally, offline queue, background sync to multiple services). This should fix ListenBrainz cache losing scrobbles, enable retry for unsynced scrobbles, make undo/sync state consistent, and allow caching history locally.
- [x] Taking 10+ seconds to load.
- [x] Stop the constant reloading of images on scroll in history view.
- [ ] Fix progress bar jumping UI, animation of bar screwing up when opening/closing app.
- [x] Stop requesting images and stuff every time we click in the progress bar.
- [ ] Fix UI for password request for Last.fm.
- [ ] Display blacklisted tracks somewhere, otherwise we have no way of knowing which tracks were blacklisted.
- [ ] Auto-update.
- [ ] Add macOS notification center alerts (for track change, for API failures...).
- [ ] Show multiple playing sources in player.
- [ ] Edit track info before/after scrobbling.
- [ ] Add metrics (with opt-out).
- [ ] Edit scrobbles (for fixing wrong metadata, or adding missing info). Maybe keep the rule (search/replace or something like that) and allow for future automatic uses and backward fixing.
- [ ] History fixer for false positives (YouTube videos scrobbled as music) with confidence threshold and user confirmation.
- [ ] Factory methods on the model violate Single Responsibility Principle. Track should be a pure data model, and conversion logic belongs in the clients/decoders.
- [ ] Update the reverse domain.
- [ ] Fix credits/dates in files.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
