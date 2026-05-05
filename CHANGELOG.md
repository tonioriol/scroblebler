# Changelog
All notable changes to this project will be documented in this file.
See [conventional commits](https://www.conventionalcommits.org/) for commit guidelines.

- - -
## [v1.1.0](https://github.com/tonioriol/scroblebler/compare/ecd7c9189adf9b4927c2a2ba1f4d8ec375f9e405..v1.1.0) - 2026-05-05
#### Features
- add Sparkle EdDSA public key - ([78f058c](https://github.com/tonioriol/scroblebler/commit/78f058ce58641efa99f0b118b596adeda48b020c)) - Toni Oriol
- switch versioning from semantic-release to cocogitto - ([7f0a765](https://github.com/tonioriol/scroblebler/commit/7f0a765486c1c79ad7b16aa398b88369b9210d75)) - Toni Oriol
- add Makefile for SPM-based app bundle assembly and signing - ([2d0fe34](https://github.com/tonioriol/scroblebler/commit/2d0fe34e22195d5d58c87e294a482c60e8015b61)) - Toni Oriol
- add Sparkle 2.x auto-update support - ([25c10f9](https://github.com/tonioriol/scroblebler/commit/25c10f96ec79588a55b8efb41d946f3d93b61ab7)) - Toni Oriol
- add music validation filter with MBID Mapper, fix Last.fm delete, add periodic sync - ([bbd3677](https://github.com/tonioriol/scroblebler/commit/bbd36775a03410db47b8af9354bd82c96352fba3)) - Toni Oriol
- add MusicKit-based backfill for iPhone/iCloud plays - ([ae6318b](https://github.com/tonioriol/scroblebler/commit/ae6318bc6022a1c54fad0888cde64d81df2f7716)) - Toni Oriol
#### Bug Fixes
- (**docs**) correct spelling errors in AGENTS.md - ([ecd7c91](https://github.com/tonioriol/scroblebler/commit/ecd7c9189adf9b4927c2a2ba1f4d8ec375f9e405)) - Toni Oriol
- Swift 6 concurrency safety for Timer and Task captures - ([bbaf858](https://github.com/tonioriol/scroblebler/commit/bbaf8587666f35e813c4bb5fd8cf4128273ef846)) - Toni Oriol
- skip legacy non-conventional commits in CI cocogitto check - ([d579356](https://github.com/tonioriol/scroblebler/commit/d57935631ca5b64a0a8fffdffe0aa4b1e6194228)) - Toni Oriol
- copy MediaRemote adapter dylib into app bundle - ([ef4abd9](https://github.com/tonioriol/scroblebler/commit/ef4abd9811d35cab5f21abfe32115218be747066)) - Toni Oriol
- offset-based history pagination, UI jumping prevention, and backfill edge detection - ([207dd47](https://github.com/tonioriol/scroblebler/commit/207dd479c06cd0372489ec293ba99179dad02c9b)) - Toni Oriol
- disk-persistent image cache with Last.fm fallback and negative caching - ([cdceff5](https://github.com/tonioriol/scroblebler/commit/cdceff5c9b7cc7d77fd24dfac5b31adc1279e862)) - Toni Oriol
- prevent soft-deleted listens from being resurrected by sync - ([30d8700](https://github.com/tonioriol/scroblebler/commit/30d870036f4d3edbe3284169be4e8d95fd33c51c)) - Toni Oriol
- decouple initial render from network calls for fast startup - ([3e93339](https://github.com/tonioriol/scroblebler/commit/3e933395ba6dcffcd52955f73e622a25cbc485c5)) - Toni Oriol
#### Documentation
- mark signing/Sparkle migration complete - ([1909921](https://github.com/tonioriol/scroblebler/commit/1909921524945a23d9f08df1e044c1d7166648c8)) - Toni Oriol
- flush signing and Sparkle progress - ([047301b](https://github.com/tonioriol/scroblebler/commit/047301b453d4ac5a49011d4966640fee53e61a3b)) - Toni Oriol
- spec for code signing, Sparkle auto-updates and build migration - ([dcf8148](https://github.com/tonioriol/scroblebler/commit/dcf8148ed44663b3f5377aa1132fcfca950a286b)) - Toni Oriol
- document play catalog tracks investigation and limitations - ([9b1d1ba](https://github.com/tonioriol/scroblebler/commit/9b1d1bafff04a121a42189297fb628bd9260268a)) - Toni Oriol
- mark image request on progress bar click TODO as done - ([c916eae](https://github.com/tonioriol/scroblebler/commit/c916eae768216a11cdaa578513f7c5da10280899)) - Toni Oriol
#### Continuous Integration
- add release pipeline with signing, notarization and appcast - ([a438556](https://github.com/tonioriol/scroblebler/commit/a4385563d632419f2b077ef7eda51944abb0b8b3)) - Toni Oriol
#### Miscellaneous Chores
- add cocogitto changelog separator - ([f17f2be](https://github.com/tonioriol/scroblebler/commit/f17f2be63d6e59ae3bcfc32280294372a8f49826)) - Toni Oriol
- add standalone Info.plist for SPM builds with Sparkle keys - ([c82b0e9](https://github.com/tonioriol/scroblebler/commit/c82b0e95b87ce4af508d5e4443cde748bb29371b)) - Toni Oriol
- generate AppIcon.icns from asset catalog PNGs - ([b4a6c11](https://github.com/tonioriol/scroblebler/commit/b4a6c113d7e0b02def7cefd1a6a5e9a59f661e56)) - Toni Oriol

- - -

# [1.0.0](https://github.com/tonioriol/scroblebler/compare/v0.3.0...v1.0.0) (2026-02-20)


### Bug Fixes

* avoid lastfm rate limit during history backfill ([d1872ba](https://github.com/tonioriol/scroblebler/commit/d1872ba67bfb98a02d1f102308031141d72b2e84))
* balance vertical spacing in now playing view ([3c80d58](https://github.com/tonioriol/scroblebler/commit/3c80d587d67ea75bf142a4e583f73494cf0a019d))
* **build:** remove obsolete cmake step for mediaremote-adapter ([e252b68](https://github.com/tonioriol/scroblebler/commit/e252b680b977c35b94514881c06c656d86ae7b83))
* correct MediaRemoteAdapter usage and fix duplicate controller instance ([23b8137](https://github.com/tonioriol/scroblebler/commit/23b81376181eefffbac97d5aaa5f80a29ab8e4ae))
* eliminate progress bar animation jank during seeking ([332e3c8](https://github.com/tonioriol/scroblebler/commit/332e3c879f400464dc61966002c00f75a88c953c))
* **history:** stabilize list row identity to prevent blank gaps ([0f20e19](https://github.com/tonioriol/scroblebler/commit/0f20e194b9ef7a1bd4f118dab66196d60a079f3c))
* improve track transition detection and prevent progress bar overflow ([5970618](https://github.com/tonioriol/scroblebler/commit/597061848cd2156eeb76c1fb8dd39081e9ea8352))
* **listenbrainz:** use track/album fallback search types ([d59d7c7](https://github.com/tonioriol/scroblebler/commit/d59d7c738ede91f26ed30b0376b3d2100f66a3c6))
* love and blacklist state not updating in now playing view ([fcc317e](https://github.com/tonioriol/scroblebler/commit/fcc317e5c04ce933c8b273224ef4f8c7b4ef46c5))
* love button now properly toggles and displays state ([f903a65](https://github.com/tonioriol/scroblebler/commit/f903a65448f78828eaf3ba93a09d4eeba89724f8))
* make services selector clickable when logged out ([27fde7f](https://github.com/tonioriol/scroblebler/commit/27fde7f2b5c334e410a93e7d93c0a4e571f093b6))
* now playing links go to correct last.fm pages instead of homepage ([08e741f](https://github.com/tonioriol/scroblebler/commit/08e741fb5e186ea9718b8ad8bc95c4b1bb36058e))
* persist history image url ([9245850](https://github.com/tonioriol/scroblebler/commit/9245850c41a16889dcda271c0b4cd5a979b0e8a3))
* preserve loved state during non-authoritative sync ([739ce18](https://github.com/tonioriol/scroblebler/commit/739ce1873544b411da02760987b832ef06bc2399))
* prevent stale now playing state from mediaremote ([38a8ca7](https://github.com/tonioriol/scroblebler/commit/38a8ca785fddb0c5f27d03d7d4b12bc0b36a48d8))
* propagate undo scrobble to follower services by passing reactive serviceInfo state ([acde2f8](https://github.com/tonioriol/scroblebler/commit/acde2f861bcfc23ab4ee7d1fe19b2e04903d1376))
* refresh now playing state ([b49661c](https://github.com/tonioriol/scroblebler/commit/b49661c9c22793e96d1b53aa5c7592684faca017))
* remove focus trap to eliminate input focus lag ([139a922](https://github.com/tonioriol/scroblebler/commit/139a9222dab92c44cf15ab066cb23f96511a06aa))
* remove stats endpoint from LB cache to prevent double-counting ([9319904](https://github.com/tonioriol/scroblebler/commit/93199040c2307a6db62742a245fcdcd2d841d5cd))
* respect blacklist in backfill service to prevent syncing to follower services ([e3dfb2e](https://github.com/tonioriol/scroblebler/commit/e3dfb2e9cbda3bc2e4de77919ebc3daacd4d9b72))
* restore history via db schema + multi-service backfill ([8d34164](https://github.com/tonioriol/scroblebler/commit/8d34164f4519740aceccb2eb559cf8aaa5bfdef4))
* restore love sync and improve focus handling ([8b2f894](https://github.com/tonioriol/scroblebler/commit/8b2f8940a031160bf74888290ceb317ced0c4f40))
* restore progress bar drag ([24ca070](https://github.com/tonioriol/scroblebler/commit/24ca070966c638d793e8f4f98a0d060fc1e195b9))
* smooth now playing to history transition ([3f84b98](https://github.com/tonioriol/scroblebler/commit/3f84b986361eb68d1ab7d20a0d56aaad9395148d))
* sync icon not refreshing during backfill ([48e75d7](https://github.com/tonioriol/scroblebler/commit/48e75d746b9d6e994f9c69b4f8c5aeecba57ce97))
* update TODO list with new tasks and completed items ([53f62d0](https://github.com/tonioriol/scroblebler/commit/53f62d0916486651582b28c36af3cf1b2f995232))
* update Xcode project to reference HistoryPlay.swift ([fe42339](https://github.com/tonioriol/scroblebler/commit/fe4233901e985c0b8ce28fc0e95dba88c0793233))
* **watcher:** ensure now playing detected on first start ([931028d](https://github.com/tonioriol/scroblebler/commit/931028d3c9402af708aaa5cc0ea3463d40ebc190))


### Features

* add bundleIdentifier field to Track model ([f93e68d](https://github.com/tonioriol/scroblebler/commit/f93e68d142761bf841b7640af47099bc77dcd96e))
* add cache invalidation button for ListenBrainz with immediate rebuild and progress logging ([a370d88](https://github.com/tonioriol/scroblebler/commit/a370d888556c3eb1f933fb5e30d406aa6f410a63))
* add collapsible service section with slide animation ([7d271ee](https://github.com/tonioriol/scroblebler/commit/7d271ee4951116cba911fe81b9d12a0306cc17f5))
* add cover art url helper ([b0d9595](https://github.com/tonioriol/scroblebler/commit/b0d9595ece3e729b5edae1ae071ab5d16eae8205))
* add delete-pending retries for optimistic deletes ([b394406](https://github.com/tonioriol/scroblebler/commit/b394406032a386e60d24ccbc968693c33774981a))
* add history search ([9006012](https://github.com/tonioriol/scroblebler/commit/9006012decc1552de9b8925758bcae5b3f6dfd94))
* add play button for history tracks ([dd91d4a](https://github.com/tonioriol/scroblebler/commit/dd91d4a9021adf206fff7a42e5e8ea7c9cc6fa14))
* add sqlite history search ([229588a](https://github.com/tonioriol/scroblebler/commit/229588aa91cef17d81990efc32b5eed96a3be574))
* add StringSimilarity utility for improved track matching and refactor findBestMatch logic ([30da44b](https://github.com/tonioriol/scroblebler/commit/30da44b6ac479bbe0d3606ac5a54dc05cf83550d))
* complete Phase 4 by simplifying sync logic, reducing lines and improving code flow ([c33c481](https://github.com/tonioriol/scroblebler/commit/c33c481bb8c0cc36519411c0d4e05e09ad4fb447))
* complete UI cleanup by removing year field, unifying player controls, and simplifying TrackInfo ([145fbe4](https://github.com/tonioriol/scroblebler/commit/145fbe47718937a05534d4883b1aaec2f40e7452))
* **database:** add SQLite storage layer with GRDB ([1ec517b](https://github.com/tonioriol/scroblebler/commit/1ec517b953a167f2955ab41ce2429aa266943043))
* enhance logging and artwork handling in media components ([98766be](https://github.com/tonioriol/scroblebler/commit/98766bef2eecec15c38e59467c273f76554e469b))
* **history:** show full date on hover ([6f00de9](https://github.com/tonioriol/scroblebler/commit/6f00de956531ffe4b34dbf0fd2dd3b9a8b3ea3e9))
* implement Jaccard similarity calculation and update similarity scoring method ([e88f917](https://github.com/tonioriol/scroblebler/commit/e88f9171bef34c4202c51c50900991caf68b6524))
* implement local-first sync engine with Track→Listen migration ([0c20f1f](https://github.com/tonioriol/scroblebler/commit/0c20f1f7695dbdbccfa16158933e3ebd6124f32f))
* implement offline operation queue and network reachability monitoring ([c9b514c](https://github.com/tonioriol/scroblebler/commit/c9b514cc381bbf48dcdd9c81d5006a5dc02d0eb9))
* integrate ejbills/mediaremote-adapter Swift package for native media control ([e5293d5](https://github.com/tonioriol/scroblebler/commit/e5293d513c45bf19c026e32a9cc2ff7ba358d75b))
* open source app from now playing artwork ([f8477e8](https://github.com/tonioriol/scroblebler/commit/f8477e80a05bc6ec3b82ba2e47b73c198274e12b))
* **phase3:** migrate ListenBrainz cache to SQLite with rate limiting ([5aadafc](https://github.com/tonioriol/scroblebler/commit/5aadafc0af6743d1c8a8cde8a73a80b25ea80a0d))
* **phase4:** implement persistent blacklist with case-insensitive sync ([b0ae8b0](https://github.com/tonioriol/scroblebler/commit/b0ae8b0b37791592b052c0637ba2567b3e147d86))
* **playback:** add play controls to now playing view ([af1a590](https://github.com/tonioriol/scroblebler/commit/af1a59001342fac1299597b08bfe506a422463aa))
* refactor client methods to remove sessionKey parameter and restore credentials on app restart ([6d0d47b](https://github.com/tonioriol/scroblebler/commit/6d0d47b57d6c0d7d48891fe6b34f65d192707c86))
* replace media-control wrapper with direct mediaremote-adapter integration for real-time streaming ([3f3f768](https://github.com/tonioriol/scroblebler/commit/3f3f76898d7067ab6e8bba75209f061fd01df62e))
* show error state (X) when track not found in library ([1d02f0f](https://github.com/tonioriol/scroblebler/commit/1d02f0f598b78d130877f3118b52c89e1b6f5c70))
* simplify track matching logic by focusing on exact timestamp matches ([2be14dc](https://github.com/tonioriol/scroblebler/commit/2be14dc4bda756755e2139dad877818aa58293db))
* update TODO list with new features and improvements ([c0fa011](https://github.com/tonioriol/scroblebler/commit/c0fa0116557d05342be6469d8e942dbeb0331e23))


### Performance Improvements

* optimize artwork loading and reduce verbose logging ([6a0c934](https://github.com/tonioriol/scroblebler/commit/6a0c934a0501e19582a6f36f49c7c361c36312f9))
* optimize history pagination with timestamp-based queries ([a87bb9b](https://github.com/tonioriol/scroblebler/commit/a87bb9b2821f3586bcb4f34f9e05f875dcd73cb8))


### Reverts

* restore original Levenshtein-based track matching with 2-min window and 80% threshold ([2136370](https://github.com/tonioriol/scroblebler/commit/2136370ac7cee9608ff9b1ea695366c6ea42dc5c))


### BREAKING CHANGES

* **phase4:** Blacklist data migrated from UserDefaults to SQLite

Features:
- Case-insensitive artist/track matching
- Global state synchronization via NotificationCenter
- Thread-safe UI updates with @MainActor
- Persistent SQLite storage with GRDB
- Cross-component sync (NowPlaying ↔ History)

Implementation:
- LocalBlacklist: Singleton service with async/await API
- BlacklistButton: Synchronized UI with notification observers
- GRDB models: Added CodingKeys for snake_case mapping
- ServiceManager: Blacklist checks before scrobble/now-playing
- UndoButton: Blacklist checks before redo operations

Fixes:
- Missing databaseTableName in BlacklistEntry & QueuedOperation
- Missing CodingKeys enums in all 4 database models
- Case mismatch between NowPlaying and History APIs
- Thread safety issues with background notifications
- View identity management for track changes

Technical Details:
- Normalize strings to lowercase for comparison
- Post notifications on main thread
- Use @MainActor for state updates
- Force view recreation with .id(trackId)
- macOS 11.0+ compatible (no .task modifier)

Timeline: 3.5 hours (estimated 2 hours)

Refs: SCROBLEBLER_REFACTOR_PLAN.md Phase 4

# [1.0.0](https://github.com/tonioriol/scroblebler/compare/v0.3.0...v1.0.0) (2026-02-20)


### Bug Fixes

* avoid lastfm rate limit during history backfill ([d1872ba](https://github.com/tonioriol/scroblebler/commit/d1872ba67bfb98a02d1f102308031141d72b2e84))
* balance vertical spacing in now playing view ([3c80d58](https://github.com/tonioriol/scroblebler/commit/3c80d587d67ea75bf142a4e583f73494cf0a019d))
* correct MediaRemoteAdapter usage and fix duplicate controller instance ([23b8137](https://github.com/tonioriol/scroblebler/commit/23b81376181eefffbac97d5aaa5f80a29ab8e4ae))
* eliminate progress bar animation jank during seeking ([332e3c8](https://github.com/tonioriol/scroblebler/commit/332e3c879f400464dc61966002c00f75a88c953c))
* **history:** stabilize list row identity to prevent blank gaps ([0f20e19](https://github.com/tonioriol/scroblebler/commit/0f20e194b9ef7a1bd4f118dab66196d60a079f3c))
* improve track transition detection and prevent progress bar overflow ([5970618](https://github.com/tonioriol/scroblebler/commit/597061848cd2156eeb76c1fb8dd39081e9ea8352))
* **listenbrainz:** use track/album fallback search types ([d59d7c7](https://github.com/tonioriol/scroblebler/commit/d59d7c738ede91f26ed30b0376b3d2100f66a3c6))
* love and blacklist state not updating in now playing view ([fcc317e](https://github.com/tonioriol/scroblebler/commit/fcc317e5c04ce933c8b273224ef4f8c7b4ef46c5))
* love button now properly toggles and displays state ([f903a65](https://github.com/tonioriol/scroblebler/commit/f903a65448f78828eaf3ba93a09d4eeba89724f8))
* make services selector clickable when logged out ([27fde7f](https://github.com/tonioriol/scroblebler/commit/27fde7f2b5c334e410a93e7d93c0a4e571f093b6))
* now playing links go to correct last.fm pages instead of homepage ([08e741f](https://github.com/tonioriol/scroblebler/commit/08e741fb5e186ea9718b8ad8bc95c4b1bb36058e))
* persist history image url ([9245850](https://github.com/tonioriol/scroblebler/commit/9245850c41a16889dcda271c0b4cd5a979b0e8a3))
* preserve loved state during non-authoritative sync ([739ce18](https://github.com/tonioriol/scroblebler/commit/739ce1873544b411da02760987b832ef06bc2399))
* prevent stale now playing state from mediaremote ([38a8ca7](https://github.com/tonioriol/scroblebler/commit/38a8ca785fddb0c5f27d03d7d4b12bc0b36a48d8))
* propagate undo scrobble to follower services by passing reactive serviceInfo state ([acde2f8](https://github.com/tonioriol/scroblebler/commit/acde2f861bcfc23ab4ee7d1fe19b2e04903d1376))
* refresh now playing state ([b49661c](https://github.com/tonioriol/scroblebler/commit/b49661c9c22793e96d1b53aa5c7592684faca017))
* remove focus trap to eliminate input focus lag ([139a922](https://github.com/tonioriol/scroblebler/commit/139a9222dab92c44cf15ab066cb23f96511a06aa))
* remove stats endpoint from LB cache to prevent double-counting ([9319904](https://github.com/tonioriol/scroblebler/commit/93199040c2307a6db62742a245fcdcd2d841d5cd))
* respect blacklist in backfill service to prevent syncing to follower services ([e3dfb2e](https://github.com/tonioriol/scroblebler/commit/e3dfb2e9cbda3bc2e4de77919ebc3daacd4d9b72))
* restore history via db schema + multi-service backfill ([8d34164](https://github.com/tonioriol/scroblebler/commit/8d34164f4519740aceccb2eb559cf8aaa5bfdef4))
* restore love sync and improve focus handling ([8b2f894](https://github.com/tonioriol/scroblebler/commit/8b2f8940a031160bf74888290ceb317ced0c4f40))
* restore progress bar drag ([24ca070](https://github.com/tonioriol/scroblebler/commit/24ca070966c638d793e8f4f98a0d060fc1e195b9))
* smooth now playing to history transition ([3f84b98](https://github.com/tonioriol/scroblebler/commit/3f84b986361eb68d1ab7d20a0d56aaad9395148d))
* sync icon not refreshing during backfill ([48e75d7](https://github.com/tonioriol/scroblebler/commit/48e75d746b9d6e994f9c69b4f8c5aeecba57ce97))
* update TODO list with new tasks and completed items ([53f62d0](https://github.com/tonioriol/scroblebler/commit/53f62d0916486651582b28c36af3cf1b2f995232))
* update Xcode project to reference HistoryPlay.swift ([fe42339](https://github.com/tonioriol/scroblebler/commit/fe4233901e985c0b8ce28fc0e95dba88c0793233))
* **watcher:** ensure now playing detected on first start ([931028d](https://github.com/tonioriol/scroblebler/commit/931028d3c9402af708aaa5cc0ea3463d40ebc190))


### Features

* add bundleIdentifier field to Track model ([f93e68d](https://github.com/tonioriol/scroblebler/commit/f93e68d142761bf841b7640af47099bc77dcd96e))
* add cache invalidation button for ListenBrainz with immediate rebuild and progress logging ([a370d88](https://github.com/tonioriol/scroblebler/commit/a370d888556c3eb1f933fb5e30d406aa6f410a63))
* add collapsible service section with slide animation ([7d271ee](https://github.com/tonioriol/scroblebler/commit/7d271ee4951116cba911fe81b9d12a0306cc17f5))
* add cover art url helper ([b0d9595](https://github.com/tonioriol/scroblebler/commit/b0d9595ece3e729b5edae1ae071ab5d16eae8205))
* add delete-pending retries for optimistic deletes ([b394406](https://github.com/tonioriol/scroblebler/commit/b394406032a386e60d24ccbc968693c33774981a))
* add history search ([9006012](https://github.com/tonioriol/scroblebler/commit/9006012decc1552de9b8925758bcae5b3f6dfd94))
* add play button for history tracks ([dd91d4a](https://github.com/tonioriol/scroblebler/commit/dd91d4a9021adf206fff7a42e5e8ea7c9cc6fa14))
* add sqlite history search ([229588a](https://github.com/tonioriol/scroblebler/commit/229588aa91cef17d81990efc32b5eed96a3be574))
* add StringSimilarity utility for improved track matching and refactor findBestMatch logic ([30da44b](https://github.com/tonioriol/scroblebler/commit/30da44b6ac479bbe0d3606ac5a54dc05cf83550d))
* complete Phase 4 by simplifying sync logic, reducing lines and improving code flow ([c33c481](https://github.com/tonioriol/scroblebler/commit/c33c481bb8c0cc36519411c0d4e05e09ad4fb447))
* complete UI cleanup by removing year field, unifying player controls, and simplifying TrackInfo ([145fbe4](https://github.com/tonioriol/scroblebler/commit/145fbe47718937a05534d4883b1aaec2f40e7452))
* **database:** add SQLite storage layer with GRDB ([1ec517b](https://github.com/tonioriol/scroblebler/commit/1ec517b953a167f2955ab41ce2429aa266943043))
* enhance logging and artwork handling in media components ([98766be](https://github.com/tonioriol/scroblebler/commit/98766bef2eecec15c38e59467c273f76554e469b))
* **history:** show full date on hover ([6f00de9](https://github.com/tonioriol/scroblebler/commit/6f00de956531ffe4b34dbf0fd2dd3b9a8b3ea3e9))
* implement Jaccard similarity calculation and update similarity scoring method ([e88f917](https://github.com/tonioriol/scroblebler/commit/e88f9171bef34c4202c51c50900991caf68b6524))
* implement local-first sync engine with Track→Listen migration ([0c20f1f](https://github.com/tonioriol/scroblebler/commit/0c20f1f7695dbdbccfa16158933e3ebd6124f32f))
* implement offline operation queue and network reachability monitoring ([c9b514c](https://github.com/tonioriol/scroblebler/commit/c9b514cc381bbf48dcdd9c81d5006a5dc02d0eb9))
* integrate ejbills/mediaremote-adapter Swift package for native media control ([e5293d5](https://github.com/tonioriol/scroblebler/commit/e5293d513c45bf19c026e32a9cc2ff7ba358d75b))
* open source app from now playing artwork ([f8477e8](https://github.com/tonioriol/scroblebler/commit/f8477e80a05bc6ec3b82ba2e47b73c198274e12b))
* **phase3:** migrate ListenBrainz cache to SQLite with rate limiting ([5aadafc](https://github.com/tonioriol/scroblebler/commit/5aadafc0af6743d1c8a8cde8a73a80b25ea80a0d))
* **phase4:** implement persistent blacklist with case-insensitive sync ([b0ae8b0](https://github.com/tonioriol/scroblebler/commit/b0ae8b0b37791592b052c0637ba2567b3e147d86))
* **playback:** add play controls to now playing view ([af1a590](https://github.com/tonioriol/scroblebler/commit/af1a59001342fac1299597b08bfe506a422463aa))
* refactor client methods to remove sessionKey parameter and restore credentials on app restart ([6d0d47b](https://github.com/tonioriol/scroblebler/commit/6d0d47b57d6c0d7d48891fe6b34f65d192707c86))
* replace media-control wrapper with direct mediaremote-adapter integration for real-time streaming ([3f3f768](https://github.com/tonioriol/scroblebler/commit/3f3f76898d7067ab6e8bba75209f061fd01df62e))
* show error state (X) when track not found in library ([1d02f0f](https://github.com/tonioriol/scroblebler/commit/1d02f0f598b78d130877f3118b52c89e1b6f5c70))
* simplify track matching logic by focusing on exact timestamp matches ([2be14dc](https://github.com/tonioriol/scroblebler/commit/2be14dc4bda756755e2139dad877818aa58293db))
* update TODO list with new features and improvements ([c0fa011](https://github.com/tonioriol/scroblebler/commit/c0fa0116557d05342be6469d8e942dbeb0331e23))


### Performance Improvements

* optimize artwork loading and reduce verbose logging ([6a0c934](https://github.com/tonioriol/scroblebler/commit/6a0c934a0501e19582a6f36f49c7c361c36312f9))
* optimize history pagination with timestamp-based queries ([a87bb9b](https://github.com/tonioriol/scroblebler/commit/a87bb9b2821f3586bcb4f34f9e05f875dcd73cb8))


### Reverts

* restore original Levenshtein-based track matching with 2-min window and 80% threshold ([2136370](https://github.com/tonioriol/scroblebler/commit/2136370ac7cee9608ff9b1ea695366c6ea42dc5c))


### BREAKING CHANGES

* **phase4:** Blacklist data migrated from UserDefaults to SQLite

Features:
- Case-insensitive artist/track matching
- Global state synchronization via NotificationCenter
- Thread-safe UI updates with @MainActor
- Persistent SQLite storage with GRDB
- Cross-component sync (NowPlaying ↔ History)

Implementation:
- LocalBlacklist: Singleton service with async/await API
- BlacklistButton: Synchronized UI with notification observers
- GRDB models: Added CodingKeys for snake_case mapping
- ServiceManager: Blacklist checks before scrobble/now-playing
- UndoButton: Blacklist checks before redo operations

Fixes:
- Missing databaseTableName in BlacklistEntry & QueuedOperation
- Missing CodingKeys enums in all 4 database models
- Case mismatch between NowPlaying and History APIs
- Thread safety issues with background notifications
- View identity management for track changes

Technical Details:
- Normalize strings to lowercase for comparison
- Post notifications on main thread
- Use @MainActor for state updates
- Force view recreation with .id(trackId)
- macOS 11.0+ compatible (no .task modifier)

Timeline: 3.5 hours (estimated 2 hours)

Refs: SCROBLEBLER_REFACTOR_PLAN.md Phase 4

# [0.3.0](https://github.com/tonioriol/scroblebler/compare/v0.2.1...v0.3.0) (2025-12-28)


### Bug Fixes

* update build script to set app version from semantic-release ([dcaf0a8](https://github.com/tonioriol/scroblebler/commit/dcaf0a8998e408e317fafaa699ea72a718c89bb4))
* update release assets and build script to include Info.plist and project.pbxproj ([b2f7b08](https://github.com/tonioriol/scroblebler/commit/b2f7b08791c8643f5da47c55ac533bcc8a62e102))


### Features

* add testing and unify exponential backoff logic to README ([bfa3e70](https://github.com/tonioriol/scroblebler/commit/bfa3e7048255b9ec8222d53552a03981ca3ef43d))

## [0.2.1](https://github.com/tonioriol/scroblebler/compare/v0.2.0...v0.2.1) (2025-12-28)


### Bug Fixes

* add retry logic for MBID mapper SSL failures ([9e31075](https://github.com/tonioriol/scroblebler/commit/9e31075c74c1dedc9e82d0a13904bee44ddb7c0b))
* resolve backfill rejection by omitting duration:0 and add love state syncing with enhanced logging ([011274d](https://github.com/tonioriol/scroblebler/commit/011274d429b73e35475a865d80bda8ba73a6ec3d))
* sync status computation issues and update UI handling ([dab86cc](https://github.com/tonioriol/scroblebler/commit/dab86cca0be1bbc66c29d67e67af79dcd2ad9e19))
* wrong images displayed when switching main service ([085218b](https://github.com/tonioriol/scroblebler/commit/085218bdedc273bdb606b82fb09f56a57dbff63c))

# [0.2.0](https://github.com/tonioriol/scroblebler/compare/v0.1.0...v0.2.0) (2025-12-28)


### Features

* update app icons and add logo variants ([78c20d7](https://github.com/tonioriol/scroblebler/commit/78c20d7ba0401b9ab3a542d3f9c8f800646c933c))

# [0.1.0](https://github.com/tonioriol/scroblebler/compare/v0.0.0...v0.1.0) (2025-12-28)


### Bug Fixes

* adjust spacing in architecture diagram for better readability ([e6e2c45](https://github.com/tonioriol/scroblebler/commit/e6e2c456ed1ce5ae3800f6077201a784bdbc5ef9))
* create Casks directory in homebrew tap workflow ([76a6ede](https://github.com/tonioriol/scroblebler/commit/76a6edec57c2aafa4e14148a3d2aa2df6008df9d))
* enable provisioning updates for CI builds ([a6954ae](https://github.com/tonioriol/scroblebler/commit/a6954aee8699c889433994b28c395f6083065efc))
* ensure scroblebler.rb is updated and committed during release ([342c93d](https://github.com/tonioriol/scroblebler/commit/342c93d02df3d47f538eed23edf27f50e6950429))
* homebrew cask livecheck syntax and download url ([cbd8694](https://github.com/tonioriol/scroblebler/commit/cbd8694238d125cfc7738a5adb22441fb8edb718))
* import provisioning profile for CI builds ([8b5fa69](https://github.com/tonioriol/scroblebler/commit/8b5fa69c7a5dffd825c240a2a5571663fb5b16a2))
* improve duration formatting and enhance layout for artist and album display in TrackInfoView ([b01f32a](https://github.com/tonioriol/scroblebler/commit/b01f32ad34f58c67d872e89efb6573c3cb0cc77a))
* improve popover stability in fullscreen mode ([62aa2d2](https://github.com/tonioriol/scroblebler/commit/62aa2d2b1f343251e9f97a7498c7eb36ff0af753))
* love/like button binding issue ([fda6514](https://github.com/tonioriol/scroblebler/commit/fda65142eca4c23c583540b8cdc6194291745acc))
* playcount and  enhance logging ([20c7c0b](https://github.com/tonioriol/scroblebler/commit/20c7c0b3bcf00ed08c31d84d4becc98141e81870))
* remove duplicate publish command ([ecbcf7d](https://github.com/tonioriol/scroblebler/commit/ecbcf7da7a02e49a9d8207c7198e12e22b6cf692))
* sed syntax for GNU sed ([6d82631](https://github.com/tonioriol/scroblebler/commit/6d82631d4b6f783504c0237e37d1e25cffa123fc))
* update component names and correct login state type in MainView ([097ab39](https://github.com/tonioriol/scroblebler/commit/097ab3919c04526a637f8a75a531fd646009c319))
* update plist path in zap trash for Scroblebler ([8e611e0](https://github.com/tonioriol/scroblebler/commit/8e611e083751af25d76c6a05dbb406624a91e6bd))
* use ad-hoc signing instead of no signing ([1d0b6d5](https://github.com/tonioriol/scroblebler/commit/1d0b6d5e679733eca2d5885aca808bd7acd0c9dc))
* use PAT for homebrew tap push ([a4787ad](https://github.com/tonioriol/scroblebler/commit/a4787ad2595f402dc8fc2fecddce580500de1b5b))


### Features

* add ad-hoc code signing to build script for DMG ([eb5be6a](https://github.com/tonioriol/scroblebler/commit/eb5be6a0b38b04959b6c1b37ee73b4241c735f1f))
* add album parameter to UndoButton and enhance scrobble functionality ([9593a51](https://github.com/tonioriol/scroblebler/commit/9593a51140a41b1fc4178f15cfffff6ceae2870d))
* add automated release workflow with semantic-release ([421d7b4](https://github.com/tonioriol/scroblebler/commit/421d7b4fd401255de2dc22a379fddfb3869a016b))
* add clickable track name links to Last.fm ([33261f9](https://github.com/tonioriol/scroblebler/commit/33261f957c46093a3a9d0163e9755f437c142bb3))
* add code signing with Apple Development certificate ([abcdf99](https://github.com/tonioriol/scroblebler/commit/abcdf9908461788d91bd3ee8f1eb9befa7bdff42))
* add cover art URL extraction for recent tracks, top artists, albums, and tracks ([e09a379](https://github.com/tonioriol/scroblebler/commit/e09a3792f3d86705f572664bbc87262dc087205c))
* add guidelines for simplicity and commit message format in AGENTS.md ([9bdf9c4](https://github.com/tonioriol/scroblebler/commit/9bdf9c42d260973cdd6e4b1ba3a0a89cc20da63c))
* add homebrew cask formula ([7373f67](https://github.com/tonioriol/scroblebler/commit/7373f6723ca940c62c83df717287df31ffbb168d))
* add homebrew tap with automated updates ([b7c9d91](https://github.com/tonioriol/scroblebler/commit/b7c9d91d89b35e937fdf2b5fef9784cc6735da8a))
* add launch configurations for debugging and releasing Audioscrobbler ([55dcb63](https://github.com/tonioriol/scroblebler/commit/55dcb63e25e4a064925e0e43a680ac2b7a6251b0))
* add love/unlove buttons to playing track and history items ([47e225e](https://github.com/tonioriol/scroblebler/commit/47e225efd49d24becb5cae9c0f9c3fffe8a7bcd7))
* add LoveButton component and integrate it into HistoryItemView and PlayingItemView ([46d4d6a](https://github.com/tonioriol/scroblebler/commit/46d4d6a54cd9b67cd2a98534b739c9263d586e3f))
* add main service preference functionality to Defaults and integrate with MainView ([dfcae91](https://github.com/tonioriol/scroblebler/commit/dfcae91bf8a25a79358272c6d069d758b52f665f))
* add manual trigger to homebrew tap workflow ([1b5e2fe](https://github.com/tonioriol/scroblebler/commit/1b5e2fe7c1f5a96ebe7496ed115c3034ea15703f))
* add marquee animation for overflowing text ([91abc9e](https://github.com/tonioriol/scroblebler/commit/91abc9ed346485a7a01825007a0b3b34afee0080))
* add notification handling for recent tracks loading and implement retry logic for API requests ([34132c9](https://github.com/tonioriol/scroblebler/commit/34132c9a42d633d2c2f55cfb9749cf009911dc91))
* add play count fetching logic to NowPlaying component ([037c6b5](https://github.com/tonioriol/scroblebler/commit/037c6b593d22354c4d1bc8a7be8d47839d9777a9))
* add play count handling in HistoryItemView and TrackInfoView ([3dcf66f](https://github.com/tonioriol/scroblebler/commit/3dcf66fba10cc37ac28c90a86f0751f48204eefc))
* add ProfileView and integrate with MainView and HeaderView ([bdc3f82](https://github.com/tonioriol/scroblebler/commit/bdc3f8227cab302ca7e0abf00ca068122e2f8099))
* add scrobble undo and blacklist functionality with code quality improvements ([a179589](https://github.com/tonioriol/scroblebler/commit/a179589a3fd0aa3f7ff26f33e7399bb0e189f010))
* add ScrollingText component and refactor Link usage in TrackInfoView for improved text display ([c38bd9b](https://github.com/tonioriol/scroblebler/commit/c38bd9b7fdb2b46bb4d7439f1dc402671aa35e95))
* add service-specific branding with logos, gradients, and colors ([1b34bb6](https://github.com/tonioriol/scroblebler/commit/1b34bb6dba57d12a42273b45c0bc131b6fd1b258))
* add TokenInputSheet component for user token input and validation in ListenBrainz integration ([0864234](https://github.com/tonioriol/scroblebler/commit/0864234227d539df81fb5a7e55a2d6e41524b4e7))
* add tooltip for overflowing text on hover ([cfb55f9](https://github.com/tonioriol/scroblebler/commit/cfb55f9799e1a45a38d971f2e309e5aaad281413))
* add TrackInfoView component and integrate it into HistoryItemView and PlayingItemView ([8540aab](https://github.com/tonioriol/scroblebler/commit/8540aabfe0e010e269681156fd373af75d86e4cc))
* auto-size container when no history and fix gitignore for xcode files ([198fd79](https://github.com/tonioriol/scroblebler/commit/198fd794172769e560c198e326528ee0517c57a7))
* automated local releases with semantic-release ([6830866](https://github.com/tonioriol/scroblebler/commit/683086683bee8e78ffae1c56668634c3b931dbda))
* clear profile picture on Last.fm logout ([e2f10b1](https://github.com/tonioriol/scroblebler/commit/e2f10b1f56b31456721e6bcec7aca8b4f8b87dc4))
* display album artwork in history and now playing ([7fbc957](https://github.com/tonioriol/scroblebler/commit/7fbc957a909ef65120a5b18df051a237ef5a2ce6))
* enhance logo rendering and update properties in asset catalog ([dcc8c3e](https://github.com/tonioriol/scroblebler/commit/dcc8c3ed949624834cf077d03bda22f85196978a))
* enhance love tracking functionality across LastFmClient and UI components ([aa6e0e1](https://github.com/tonioriol/scroblebler/commit/aa6e0e11c45767628c61d9bbd28d886c32313f6d))
* enhance LoveButton UI with service availability checks and improved accessibility ([be0ad9a](https://github.com/tonioriol/scroblebler/commit/be0ad9a05e6be6e9c82e390ca6309c86f3723c30))
* enhance MainView layout and add AnimatedHeaderView; improve ProfileView design with new back button and stat cards ([37b611f](https://github.com/tonioriol/scroblebler/commit/37b611ff78340c7412e248e0783a0ba5db4311c9))
* enhance playcount management across HistoryItem, NowPlaying, TrackInfo, and UndoButton components ([07f4e74](https://github.com/tonioriol/scroblebler/commit/07f4e74b93e8666bf96da5c1cfc5e9fd406c0f06))
* enhance ProfileView layout with improved stats display and add InfoRow component for member info ([caddefc](https://github.com/tonioriol/scroblebler/commit/caddefcd271818a2c75566ebbf9ca91c7edda16d))
* enhance ProfileView with top artists, albums, and tracks sections; update WebService to support new user stats ([d493b5e](https://github.com/tonioriol/scroblebler/commit/d493b5ef14e13e4b87ae2593889c4643d77794f7))
* enhance track matching logic with detailed logging and improved similarity scoring ([375da42](https://github.com/tonioriol/scroblebler/commit/375da4299cecd916badba29bbd88d0d0a3f9bfe8))
* enhance track playcount functionality across LastFmClient, LibreFmClient, and ListenBrainzClient ([43bb6f1](https://github.com/tonioriol/scroblebler/commit/43bb6f16033bac18a635d54b8093dbbfefba4e7a))
* enhance UI components with consistent button styles and improved action handling ([652efe2](https://github.com/tonioriol/scroblebler/commit/652efe279a1ac411fd10266b94ac218fa54ce0c5))
* enrich track information with URLs and update NowPlaying component ([dd2f148](https://github.com/tonioriol/scroblebler/commit/dd2f148cf703fb125eb835143ef3ade5fbda7d33))
* implement bidirectional sync with automatic backfill across all services ([8c7bf27](https://github.com/tonioriol/scroblebler/commit/8c7bf27c9c4e00ab2440fe065ca21ccc7ad83e0f))
* implement focus trap for accessibility and remove focusable attributes from service buttons ([5801687](https://github.com/tonioriol/scroblebler/commit/5801687f3bace3987d8f4441e317c25f21a48331))
* implement image caching mechanism and preload images for tracks ([5decb1f](https://github.com/tonioriol/scroblebler/commit/5decb1f4d2e25556415f1da6de7e413f35bb0ce3))
* implement Last.fm web client for scrobble deletion and auto-authentication using Keychain ([1404f1f](https://github.com/tonioriol/scroblebler/commit/1404f1f9e33a33ccf78101dab8102bd173f3fde1))
* implement lazy loading for recent tracks in MainView ([34f21b9](https://github.com/tonioriol/scroblebler/commit/34f21b90986f3c2307f3aa96ec97977156e11224))
* implement MBID lookup for tracks and enrich URLs in TrackInfo ([b0dbc2b](https://github.com/tonioriol/scroblebler/commit/b0dbc2b93fabddbf4dab71c39f626ff28ebef4f0))
* implement pagination state management for recent tracks in ListenBrainzClient and enhance loading logic in MainView ([9544e21](https://github.com/tonioriol/scroblebler/commit/9544e215d719fd2649b7aaa90d746fb34d64e208))
* implement play count fetching for tracks in TrackInfoView ([2a1eceb](https://github.com/tonioriol/scroblebler/commit/2a1ecebeff95dcfd94416f1696a64ee50c469495))
* implement recent tracks feature with HistoryItemView ([f9284a0](https://github.com/tonioriol/scroblebler/commit/f9284a0613ba02166156af8d7691bbe83fe28f45))
* implement StringSimilarity utility and refactor track fetching logic to prioritize primary service ([97a8efc](https://github.com/tonioriol/scroblebler/commit/97a8efcee48ebe6b8fec661906e5827285a7f280))
* implement thread-safe caching for playcounts in ListenBrainzClient ([a6f208f](https://github.com/tonioriol/scroblebler/commit/a6f208f7618fd3718978941aa4f9c45d8a460067))
* implement updateLove functionality for LastFmClient and ListenBrainzClient ([60d5acf](https://github.com/tonioriol/scroblebler/commit/60d5acfa75333275c386d46e2fc0841a01cc4f3d))
* optimize playcount fetching and caching in TrackInfo component ([bc3dbac](https://github.com/tonioriol/scroblebler/commit/bc3dbac9814fc0fa248191310681dcbf29f0f9a0))
* refactor and rename components; replace HeaderView with Header, HistoryItemView with HistoryItem, PlayingItemView with NowPlaying, and TrackInfoView with TrackInfo; update related references ([37fc132](https://github.com/tonioriol/scroblebler/commit/37fc132ab2c27bc18fa94e45ec38c1633e7a6fcc))
* refactor MarqueeText component for improved scrolling logic and hover behavior ([5f2c331](https://github.com/tonioriol/scroblebler/commit/5f2c3318e913485144ba68da514ad1b995992334))
* refactor private session handling and update status bar icon logic ([d9e3d0c](https://github.com/tonioriol/scroblebler/commit/d9e3d0c9a31dd35d738bd1530b80285d2c955618))
* reload history and profile when main service changes ([7cffd98](https://github.com/tonioriol/scroblebler/commit/7cffd989e15eac33ae1e83c5001ea35abc54d305))
* rename MainContentView to ContentView and implement ContentView structure ([e87ce10](https://github.com/tonioriol/scroblebler/commit/e87ce1096861b466c5ea979171e8cd1e59c1a8c3))
* replace ScrollingText with MarqueeText component for improved text animation in TrackInfoView ([bec454f](https://github.com/tonioriol/scroblebler/commit/bec454fa41f19571f1c8086c9f5862456ef5aa09))
* simplify artwork image handling in TrackInfo component ([c3cc6d8](https://github.com/tonioriol/scroblebler/commit/c3cc6d8fa49d0cb67fe70bf4d74645af657842da))
* update data models and refactor client methods for consistency across the application ([574657f](https://github.com/tonioriol/scroblebler/commit/574657f340989095935ea238a98bb5b3fb0b03bf))
* update HistoryItemView and PlayingItemView layouts for improved spacing and organization of the like button ([b6a85ff](https://github.com/tonioriol/scroblebler/commit/b6a85ff265fd5eabecadca50c58f23d36ef7f1f3))
* update LastFmClient API keys and enhance MainView with popover display on auth success ([aabfd0c](https://github.com/tonioriol/scroblebler/commit/aabfd0c5dc383fb974e78ac1fdff033948803089))
* update launch configurations and add scheme management for Scroblebler ([d8d0fed](https://github.com/tonioriol/scroblebler/commit/d8d0fedd4a7bd3232031934c31e9a4cfff18b6da))
* update link text in AnimatedHeaderView to reflect selected service name ([5f24e39](https://github.com/tonioriol/scroblebler/commit/5f24e3971d4a721ffd19372de6942bee777c971a))
* update MainView to allow profile view to slide up from bottom; adjust opacity to offset for smoother transitions ([f046e75](https://github.com/tonioriol/scroblebler/commit/f046e7507a9cd43292577e4a83550582fb37d29f))
* update service toggle logic and improve main service preference handling ([78c8245](https://github.com/tonioriol/scroblebler/commit/78c82450e28485e0e56c57f876f030555c941b35))

# [0.1.0](https://github.com/tonioriol/scroblebler/compare/v0.0.0...v0.1.0) (2025-12-28)


### Bug Fixes

* adjust spacing in architecture diagram for better readability ([e6e2c45](https://github.com/tonioriol/scroblebler/commit/e6e2c456ed1ce5ae3800f6077201a784bdbc5ef9))
* create Casks directory in homebrew tap workflow ([76a6ede](https://github.com/tonioriol/scroblebler/commit/76a6edec57c2aafa4e14148a3d2aa2df6008df9d))
* enable provisioning updates for CI builds ([a6954ae](https://github.com/tonioriol/scroblebler/commit/a6954aee8699c889433994b28c395f6083065efc))
* ensure scroblebler.rb is updated and committed during release ([342c93d](https://github.com/tonioriol/scroblebler/commit/342c93d02df3d47f538eed23edf27f50e6950429))
* homebrew cask livecheck syntax and download url ([cbd8694](https://github.com/tonioriol/scroblebler/commit/cbd8694238d125cfc7738a5adb22441fb8edb718))
* import provisioning profile for CI builds ([8b5fa69](https://github.com/tonioriol/scroblebler/commit/8b5fa69c7a5dffd825c240a2a5571663fb5b16a2))
* improve duration formatting and enhance layout for artist and album display in TrackInfoView ([b01f32a](https://github.com/tonioriol/scroblebler/commit/b01f32ad34f58c67d872e89efb6573c3cb0cc77a))
* improve popover stability in fullscreen mode ([62aa2d2](https://github.com/tonioriol/scroblebler/commit/62aa2d2b1f343251e9f97a7498c7eb36ff0af753))
* love/like button binding issue ([fda6514](https://github.com/tonioriol/scroblebler/commit/fda65142eca4c23c583540b8cdc6194291745acc))
* playcount and  enhance logging ([20c7c0b](https://github.com/tonioriol/scroblebler/commit/20c7c0b3bcf00ed08c31d84d4becc98141e81870))
* remove duplicate publish command ([ecbcf7d](https://github.com/tonioriol/scroblebler/commit/ecbcf7da7a02e49a9d8207c7198e12e22b6cf692))
* sed syntax for GNU sed ([6d82631](https://github.com/tonioriol/scroblebler/commit/6d82631d4b6f783504c0237e37d1e25cffa123fc))
* update component names and correct login state type in MainView ([097ab39](https://github.com/tonioriol/scroblebler/commit/097ab3919c04526a637f8a75a531fd646009c319))
* update plist path in zap trash for Scroblebler ([8e611e0](https://github.com/tonioriol/scroblebler/commit/8e611e083751af25d76c6a05dbb406624a91e6bd))
* use ad-hoc signing instead of no signing ([1d0b6d5](https://github.com/tonioriol/scroblebler/commit/1d0b6d5e679733eca2d5885aca808bd7acd0c9dc))
* use PAT for homebrew tap push ([a4787ad](https://github.com/tonioriol/scroblebler/commit/a4787ad2595f402dc8fc2fecddce580500de1b5b))


### Features

* add ad-hoc code signing to build script for DMG ([eb5be6a](https://github.com/tonioriol/scroblebler/commit/eb5be6a0b38b04959b6c1b37ee73b4241c735f1f))
* add album parameter to UndoButton and enhance scrobble functionality ([9593a51](https://github.com/tonioriol/scroblebler/commit/9593a51140a41b1fc4178f15cfffff6ceae2870d))
* add automated release workflow with semantic-release ([421d7b4](https://github.com/tonioriol/scroblebler/commit/421d7b4fd401255de2dc22a379fddfb3869a016b))
* add clickable track name links to Last.fm ([33261f9](https://github.com/tonioriol/scroblebler/commit/33261f957c46093a3a9d0163e9755f437c142bb3))
* add code signing with Apple Development certificate ([abcdf99](https://github.com/tonioriol/scroblebler/commit/abcdf9908461788d91bd3ee8f1eb9befa7bdff42))
* add cover art URL extraction for recent tracks, top artists, albums, and tracks ([e09a379](https://github.com/tonioriol/scroblebler/commit/e09a3792f3d86705f572664bbc87262dc087205c))
* add guidelines for simplicity and commit message format in AGENTS.md ([9bdf9c4](https://github.com/tonioriol/scroblebler/commit/9bdf9c42d260973cdd6e4b1ba3a0a89cc20da63c))
* add homebrew cask formula ([7373f67](https://github.com/tonioriol/scroblebler/commit/7373f6723ca940c62c83df717287df31ffbb168d))
* add homebrew tap with automated updates ([b7c9d91](https://github.com/tonioriol/scroblebler/commit/b7c9d91d89b35e937fdf2b5fef9784cc6735da8a))
* add launch configurations for debugging and releasing Audioscrobbler ([55dcb63](https://github.com/tonioriol/scroblebler/commit/55dcb63e25e4a064925e0e43a680ac2b7a6251b0))
* add love/unlove buttons to playing track and history items ([47e225e](https://github.com/tonioriol/scroblebler/commit/47e225efd49d24becb5cae9c0f9c3fffe8a7bcd7))
* add LoveButton component and integrate it into HistoryItemView and PlayingItemView ([46d4d6a](https://github.com/tonioriol/scroblebler/commit/46d4d6a54cd9b67cd2a98534b739c9263d586e3f))
* add main service preference functionality to Defaults and integrate with MainView ([dfcae91](https://github.com/tonioriol/scroblebler/commit/dfcae91bf8a25a79358272c6d069d758b52f665f))
* add manual trigger to homebrew tap workflow ([1b5e2fe](https://github.com/tonioriol/scroblebler/commit/1b5e2fe7c1f5a96ebe7496ed115c3034ea15703f))
* add marquee animation for overflowing text ([91abc9e](https://github.com/tonioriol/scroblebler/commit/91abc9ed346485a7a01825007a0b3b34afee0080))
* add notification handling for recent tracks loading and implement retry logic for API requests ([34132c9](https://github.com/tonioriol/scroblebler/commit/34132c9a42d633d2c2f55cfb9749cf009911dc91))
* add play count fetching logic to NowPlaying component ([037c6b5](https://github.com/tonioriol/scroblebler/commit/037c6b593d22354c4d1bc8a7be8d47839d9777a9))
* add play count handling in HistoryItemView and TrackInfoView ([3dcf66f](https://github.com/tonioriol/scroblebler/commit/3dcf66fba10cc37ac28c90a86f0751f48204eefc))
* add ProfileView and integrate with MainView and HeaderView ([bdc3f82](https://github.com/tonioriol/scroblebler/commit/bdc3f8227cab302ca7e0abf00ca068122e2f8099))
* add scrobble undo and blacklist functionality with code quality improvements ([a179589](https://github.com/tonioriol/scroblebler/commit/a179589a3fd0aa3f7ff26f33e7399bb0e189f010))
* add ScrollingText component and refactor Link usage in TrackInfoView for improved text display ([c38bd9b](https://github.com/tonioriol/scroblebler/commit/c38bd9b7fdb2b46bb4d7439f1dc402671aa35e95))
* add service-specific branding with logos, gradients, and colors ([1b34bb6](https://github.com/tonioriol/scroblebler/commit/1b34bb6dba57d12a42273b45c0bc131b6fd1b258))
* add TokenInputSheet component for user token input and validation in ListenBrainz integration ([0864234](https://github.com/tonioriol/scroblebler/commit/0864234227d539df81fb5a7e55a2d6e41524b4e7))
* add tooltip for overflowing text on hover ([cfb55f9](https://github.com/tonioriol/scroblebler/commit/cfb55f9799e1a45a38d971f2e309e5aaad281413))
* add TrackInfoView component and integrate it into HistoryItemView and PlayingItemView ([8540aab](https://github.com/tonioriol/scroblebler/commit/8540aabfe0e010e269681156fd373af75d86e4cc))
* auto-size container when no history and fix gitignore for xcode files ([198fd79](https://github.com/tonioriol/scroblebler/commit/198fd794172769e560c198e326528ee0517c57a7))
* automated local releases with semantic-release ([6830866](https://github.com/tonioriol/scroblebler/commit/683086683bee8e78ffae1c56668634c3b931dbda))
* clear profile picture on Last.fm logout ([e2f10b1](https://github.com/tonioriol/scroblebler/commit/e2f10b1f56b31456721e6bcec7aca8b4f8b87dc4))
* display album artwork in history and now playing ([7fbc957](https://github.com/tonioriol/scroblebler/commit/7fbc957a909ef65120a5b18df051a237ef5a2ce6))
* enhance logo rendering and update properties in asset catalog ([dcc8c3e](https://github.com/tonioriol/scroblebler/commit/dcc8c3ed949624834cf077d03bda22f85196978a))
* enhance love tracking functionality across LastFmClient and UI components ([aa6e0e1](https://github.com/tonioriol/scroblebler/commit/aa6e0e11c45767628c61d9bbd28d886c32313f6d))
* enhance LoveButton UI with service availability checks and improved accessibility ([be0ad9a](https://github.com/tonioriol/scroblebler/commit/be0ad9a05e6be6e9c82e390ca6309c86f3723c30))
* enhance MainView layout and add AnimatedHeaderView; improve ProfileView design with new back button and stat cards ([37b611f](https://github.com/tonioriol/scroblebler/commit/37b611ff78340c7412e248e0783a0ba5db4311c9))
* enhance playcount management across HistoryItem, NowPlaying, TrackInfo, and UndoButton components ([07f4e74](https://github.com/tonioriol/scroblebler/commit/07f4e74b93e8666bf96da5c1cfc5e9fd406c0f06))
* enhance ProfileView layout with improved stats display and add InfoRow component for member info ([caddefc](https://github.com/tonioriol/scroblebler/commit/caddefcd271818a2c75566ebbf9ca91c7edda16d))
* enhance ProfileView with top artists, albums, and tracks sections; update WebService to support new user stats ([d493b5e](https://github.com/tonioriol/scroblebler/commit/d493b5ef14e13e4b87ae2593889c4643d77794f7))
* enhance track matching logic with detailed logging and improved similarity scoring ([375da42](https://github.com/tonioriol/scroblebler/commit/375da4299cecd916badba29bbd88d0d0a3f9bfe8))
* enhance track playcount functionality across LastFmClient, LibreFmClient, and ListenBrainzClient ([43bb6f1](https://github.com/tonioriol/scroblebler/commit/43bb6f16033bac18a635d54b8093dbbfefba4e7a))
* enhance UI components with consistent button styles and improved action handling ([652efe2](https://github.com/tonioriol/scroblebler/commit/652efe279a1ac411fd10266b94ac218fa54ce0c5))
* enrich track information with URLs and update NowPlaying component ([dd2f148](https://github.com/tonioriol/scroblebler/commit/dd2f148cf703fb125eb835143ef3ade5fbda7d33))
* implement bidirectional sync with automatic backfill across all services ([8c7bf27](https://github.com/tonioriol/scroblebler/commit/8c7bf27c9c4e00ab2440fe065ca21ccc7ad83e0f))
* implement focus trap for accessibility and remove focusable attributes from service buttons ([5801687](https://github.com/tonioriol/scroblebler/commit/5801687f3bace3987d8f4441e317c25f21a48331))
* implement image caching mechanism and preload images for tracks ([5decb1f](https://github.com/tonioriol/scroblebler/commit/5decb1f4d2e25556415f1da6de7e413f35bb0ce3))
* implement Last.fm web client for scrobble deletion and auto-authentication using Keychain ([1404f1f](https://github.com/tonioriol/scroblebler/commit/1404f1f9e33a33ccf78101dab8102bd173f3fde1))
* implement lazy loading for recent tracks in MainView ([34f21b9](https://github.com/tonioriol/scroblebler/commit/34f21b90986f3c2307f3aa96ec97977156e11224))
* implement MBID lookup for tracks and enrich URLs in TrackInfo ([b0dbc2b](https://github.com/tonioriol/scroblebler/commit/b0dbc2b93fabddbf4dab71c39f626ff28ebef4f0))
* implement pagination state management for recent tracks in ListenBrainzClient and enhance loading logic in MainView ([9544e21](https://github.com/tonioriol/scroblebler/commit/9544e215d719fd2649b7aaa90d746fb34d64e208))
* implement play count fetching for tracks in TrackInfoView ([2a1eceb](https://github.com/tonioriol/scroblebler/commit/2a1ecebeff95dcfd94416f1696a64ee50c469495))
* implement recent tracks feature with HistoryItemView ([f9284a0](https://github.com/tonioriol/scroblebler/commit/f9284a0613ba02166156af8d7691bbe83fe28f45))
* implement StringSimilarity utility and refactor track fetching logic to prioritize primary service ([97a8efc](https://github.com/tonioriol/scroblebler/commit/97a8efcee48ebe6b8fec661906e5827285a7f280))
* implement thread-safe caching for playcounts in ListenBrainzClient ([a6f208f](https://github.com/tonioriol/scroblebler/commit/a6f208f7618fd3718978941aa4f9c45d8a460067))
* implement updateLove functionality for LastFmClient and ListenBrainzClient ([60d5acf](https://github.com/tonioriol/scroblebler/commit/60d5acfa75333275c386d46e2fc0841a01cc4f3d))
* optimize playcount fetching and caching in TrackInfo component ([bc3dbac](https://github.com/tonioriol/scroblebler/commit/bc3dbac9814fc0fa248191310681dcbf29f0f9a0))
* refactor and rename components; replace HeaderView with Header, HistoryItemView with HistoryItem, PlayingItemView with NowPlaying, and TrackInfoView with TrackInfo; update related references ([37fc132](https://github.com/tonioriol/scroblebler/commit/37fc132ab2c27bc18fa94e45ec38c1633e7a6fcc))
* refactor MarqueeText component for improved scrolling logic and hover behavior ([5f2c331](https://github.com/tonioriol/scroblebler/commit/5f2c3318e913485144ba68da514ad1b995992334))
* refactor private session handling and update status bar icon logic ([d9e3d0c](https://github.com/tonioriol/scroblebler/commit/d9e3d0c9a31dd35d738bd1530b80285d2c955618))
* reload history and profile when main service changes ([7cffd98](https://github.com/tonioriol/scroblebler/commit/7cffd989e15eac33ae1e83c5001ea35abc54d305))
* rename MainContentView to ContentView and implement ContentView structure ([e87ce10](https://github.com/tonioriol/scroblebler/commit/e87ce1096861b466c5ea979171e8cd1e59c1a8c3))
* replace ScrollingText with MarqueeText component for improved text animation in TrackInfoView ([bec454f](https://github.com/tonioriol/scroblebler/commit/bec454fa41f19571f1c8086c9f5862456ef5aa09))
* simplify artwork image handling in TrackInfo component ([c3cc6d8](https://github.com/tonioriol/scroblebler/commit/c3cc6d8fa49d0cb67fe70bf4d74645af657842da))
* update data models and refactor client methods for consistency across the application ([574657f](https://github.com/tonioriol/scroblebler/commit/574657f340989095935ea238a98bb5b3fb0b03bf))
* update HistoryItemView and PlayingItemView layouts for improved spacing and organization of the like button ([b6a85ff](https://github.com/tonioriol/scroblebler/commit/b6a85ff265fd5eabecadca50c58f23d36ef7f1f3))
* update LastFmClient API keys and enhance MainView with popover display on auth success ([aabfd0c](https://github.com/tonioriol/scroblebler/commit/aabfd0c5dc383fb974e78ac1fdff033948803089))
* update launch configurations and add scheme management for Scroblebler ([d8d0fed](https://github.com/tonioriol/scroblebler/commit/d8d0fedd4a7bd3232031934c31e9a4cfff18b6da))
* update link text in AnimatedHeaderView to reflect selected service name ([5f24e39](https://github.com/tonioriol/scroblebler/commit/5f24e3971d4a721ffd19372de6942bee777c971a))
* update MainView to allow profile view to slide up from bottom; adjust opacity to offset for smoother transitions ([f046e75](https://github.com/tonioriol/scroblebler/commit/f046e7507a9cd43292577e4a83550582fb37d29f))
* update service toggle logic and improve main service preference handling ([78c8245](https://github.com/tonioriol/scroblebler/commit/78c82450e28485e0e56c57f876f030555c941b35))
