# GameNative → Steam Mobile iOS integration

Source studied: [utkarshdalal/GameNative](https://github.com/utkarshdalal/GameNative) (GPL-3.0),
particularly `SteamService.kt`, `AchievementWatcher.kt`,
`StatsAchievementsGenerator.kt`, `VdfParser.kt`,
`SteamPipeServer.java` and `EpicGameLauncher.kt`.
This integration is conceptually adapted to Swift; it does not include or
redistribute GameNative's Android, Linux or Windows executable binaries.

## Implemented now

- Steam's own CM protocol `ClientGetUserStats` (818) /
  `ClientGetUserStatsResponse` (819), via the existing authenticated
  `SteamSession.sendAndWait`. **No extra account login**, no public API
  keys, no Steam password or tokens sent to new services.
- Strict bounds-checked Swift binary KeyValues parser (recursive sections,
  strings, int32/int64) and a Steam protobuf stats-response decoder.
- Maps real per-game achievement names, descriptions and bit timestamps
  from Steam's response schema to the signed-in account.
- Real achievement progress list in the iOS Achievements tab with a
  per-game selector and refresh action. Fails if Steam reports an error.
- Never connects a competing app Steam session while Madeira Dock /
  Valve's game client holds the account. Games keep their existing real
  Steam client path; refresh after gameplay.

- Notification deduplication persists per hashed account and game, based only
  on confirmed server reads. Account changes invalidate pending UI responses.
  The selector includes the complete owned-game list. These additions still
  require native compilation and real account testing.

## Not completed (do NOT label as working)

- **Automatically writing achievement unlocks back to Steam:** GameNative
  uses JavaSteam's authenticated `storeUserStats`, schema-mapped achievement
  blocks and a local `AchievementWatcher` over GSE achievement files.
  Madeira requires an iOS-compatible real per-game Steam API callback bridge
  and verified GameNative-equivalent backend acknowledgment. This PR has
  neither added a fake `steam_api64.dll` nor sent untrusted local JSON
  values to Steam. The UI shows *confirmed* Steam state.
- Popups for newly earned game achievements, live cloud write retries and
  offline-to-online synchronization.
- GameNative's Android-only Java/Kotlin services, Box64, Linux Wine,
  Winlator containers, Android Compose, native Android notifications.
- Epic/GOG login and full launcher process integration: Madeira's existing
  Wine EXE importer remains available; this is not functional EA App
  authentication or Epic/GOG DRM support.

## EA App and EA Javelin

EA App users may need a working Wine installer, WebView,
network/TLS authentication and launcher subprocess lifetime management.
The Windows kernel-mode EA Javelin driver is not supported by iOS/Wine:
neither an EXE importer nor a UI toggle can supply kernel-mode
Windows driver APIs. A publisher-supported non-kernel path or
running the game on an authorized Windows host would be required
for protected titles. This project does not counterfeit integrity
attestations or bypass anti-cheat.

## Build and tests

The new Swift reader is applied by
`SteamMobile/tools/patch_gamenative_achievements.py`, tested in Linux
source validation, and compiled by the macOS Xcode diagnostic pipeline.
All three Wine archives now build from source. The LLVM/DXMT and final Xcode
link fixes await native CI. The user supplied validated local x64 CRT inputs.
See NATIVE_REBUILD.md for the exact build state. Source
integration is not proof that the server accepts every account/game response
or that a game unlock reaches Steam.

## Licensing

The conceptual code adaptation from GameNative's GPL-3.0 sources must
retain GPL provenance and compatible redistributable source under the
project's licenses. GameNative's Android-only binary dependencies have
not been bundled. See `SteamMobile/README.md` for Madeira's baseline license.
