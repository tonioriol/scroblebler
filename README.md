# Scroblebler for Apple Music

<img src="imgs/icon.png" height="64" align="right">

Scroblebler is a native macOS application capable of scrobbling tracks from Apple Music (even when
they are not in your library).

## Features

- 🎵 **Multiple Scrobbling Services**: Support for Last.fm, ListenBrainz, and Libre.fm
- ❤️ **Track Loving**: Love/unlove tracks directly from the app
- 🚫 **Blacklist Management**: Blacklist tracks to prevent unwanted scrobbles
- ↩️ **Undo Support**: Undo recent scrobbles
- 📊 **Play Count Display**: View play counts for your tracks
- 📜 **Listening History**: Browse your recent scrobbles
- 👤 **Profile View**: View your scrobbling profile information
- 🎨 **Album Artwork**: Display beautiful album artwork
- 📱 **Now Playing**: Real-time now playing updates
- 🔐 **Multiple Authentication Methods**: Token-based and password-based authentication
- 🎯 **Smart Track Matching**: String similarity algorithms for accurate track matching
- 🪵 **Comprehensive Logging**: Detailed logging for troubleshooting
- 🚀 **Launch at Startup**: Automatically start scrobbling when you log in

## Screenshot

<img src="imgs/as-screenshot.png" height="353" />

## Installing

### Homebrew

```bash
brew install --cask https://raw.githubusercontent.com/tonioriol/scroblebler/main/scroblebler.rb
```

### Manual Installation

Signed and Notarized version is available on the [Releases](https://github.com/tonioriol/scroblebler/releases) page.

## Building

1. Clone this repository
2. Open `Scroblebler.xcodeproj`, and build it.

## Credits

This project is a fork and continuation of the original [Audioscrobbler](https://github.com/heyvito/audioscrobbler) by Victor Gama, with additional features.

## Oh no, you pushed your token and secret!

Yep. I know! There's not much one can do with the API, and even Last.fm's tokens are [available
on their repository](https://github.com/lastfm/lastfm-desktop/blob/9ae84cf4ab204a92e6953abe14026df70c140519/lib/unicorn/UnicornCoreApplication.cpp#L58)

## Known Issues

- Music.app may restart immediately after quiting. I intend to fix this in the near future.

## TODO

- [x] Sign, Notarize & Provide DMG installer
- [x] Start at Login
- [ ] Use proper logger
- [ ] Update the date and the (c) of the new files.
- [ ] Update the reverse domain.
- [ ] Offline support
- [ ] Auto-update

## License

Last.fm, Scroblebler © 2022 Last.fm Ltd. All rights reserved

```
The MIT License (MIT)

Copyright (c) 2022-2023 Victor Gama

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```
