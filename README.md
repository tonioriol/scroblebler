# Scroblebler for Apple Music

<img src="imgs/logo.svg" height="64" align="right">

Scroblebler is a native macOS application capable of scrobbling tracks from Apple Music (even when
they are not in your library).

## Features

- **Multiple Scrobbling Services**: Support for Last.fm, ListenBrainz, and Libre.fm
- **Unidirectional Sync**: Sync your listening history from a primary service to secondary services
- **Service-Specific Branding**: Visual indicators for each scrobbling service with logos and colors
- **Track Loving**: Love/unlove tracks directly from the app
- **Blacklist Management**: Blacklist tracks to prevent unwanted scrobbles
- **Undo Support**: Undo recent scrobbles
- **Play Count Display**: View play counts for your tracks
- **Listening History**: Browse your recent scrobbles with detailed track information and links
- **Profile View**: View your scrobbling profile with avatar and statistics
- **Album Artwork**: Display beautiful album artwork
- **Now Playing**: Real-time now playing updates
- **Launch at Startup**: Automatically start scrobbling when you log in

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

## Testing

Run the test suite:
```bash
swift test
```

Run specific test suites:
```bash
swift test --filter E2ETests
swift test --filter WatcherLogicTests
```

Run with verbose output:
```bash
swift test --verbose
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
- [ ] Local-first storage + sync engine (store scrobbles locally, offline queue, background sync to multiple services). This should fix ListenBrainz cache losing scrobbles, enable retry for unsynced scrobbles, make undo/sync state consistent, and allow caching history locally.
- [ ] taking 10+ seconds to load
- [ ] Stop the constant reloading of images on scroll in history view.
- [ ] Fix progress bar jumping ui, animation of bar screwing up when opening/closing app.
- [ ] stop requesting images and stuff every time we click in the progress bar.
- [ ] fix ui for password request for lastfm.
- [ ] display blacklisted tracks somewhere, otherwise we have no way of knowing which tracks were blacklisted. Only when playing them.
- [ ] Auto-update.
- [ ] Add macOS notification center alerts (for tracck change, for API failures...).
- [ ] detect non music playback (from browser, podcasts, videos, system sounds...).
- [ ] Show multiple playing sources in player.
- [ ] edit track info before/after scrobbling.
- [ ] Add metrics (with opt-out).
- [ ] Is TrackIdentity the right approach? what is it??? what is canonicalKey? coul we use messybraibrainz ids? to standardize across services?
- [ ] Factory methods on the model violate Single Responsibility Principle. Track should be a pure data model, and conversion logic belongs in the clients/decoders.
- [ ] Update the reverse domain.
- [ ] Update the date and the (c) of the new files.
- [ ] Fix credits in files.
- [ ] display full date on hover.
- [ ] Filter out youtube (or any other non music from browser crap) (use AI?)
- [ ] Edit scrobbles (for fixing wrong metadata, or adding missing info). Maybe keep the rule (search/replace or something like that) and allow for future automatic uses and backward fixing.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
