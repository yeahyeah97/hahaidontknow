# Steam Mobile — experimental native engine (SM-001)

This is an isolated development workspace in the **steam-mobile-engine-sm001** branch of `yeahyeah97/hahaidontknow`. The existing MilazyKeyboard app on `main` is unchanged. This is **not yet a validated compiled optimized IPA**.


## SM-002 optimization and build integrity work (experimental)

The Steam Mobile branch adds these **actual native source patches**, which only
take effect after a successful rebuild of Madeira and its dependencies:

- **DXMT D3D9 recursive-lock fast path:** retained from SM-001. Lock recursion
  on the owning thread avoids a redundant atomic compare-and-swap.
- **DXMT low-spin contention experiment:** `STEAM_MOBILE_D9_LOW_SPIN=1` uses
  128 pause spins per contended round instead of 2000, potentially reducing
  wasted CPU power on a parked GPU-fence owner. The default stays at upstream's
  original 2000 spins. This setting is not proven to increase game FPS.
- **Wine/iOS input:** retained bounded FIFO batching and opt-in per-event
  tracing; every input stays in order and callbacks happen after unlocking.
- **FEX JIT allocation logging:** successful allocations no longer incur a
  synchronous stderr + os_log message by default. Exhaustion/errors are never
  hidden. `STEAM_MOBILE_JIT_TRACE=1` restores successful-allocation logging.
- **Build authenticity:** a native FEX bridge marker is linked into the
  executable; `verify_optimized_ipa.py` rejects an unsigned package without
  this marker, the JIT extension, the ARM64EC translator and Microsoft VC
  runtime DLLs. It cannot prove Steam sign-in, JIT authorization or actual FPS.

GitHub CI compiles and stress-tests the real patched DXMT lock on Linux, plus
checks Wine/FEX source changes, both DX9 contention settings and the package
rejection guard. Linux host validation is **not** an iPhone runtime test.

The macOS native build needs the true FEX, Wine, DXMT, FFmpeg, JIT-pairing and
other archives plus the Microsoft VC redistributable under its own license.
See `BUILD_STATUS.md` and `docs/NATIVE_REBUILD.md`. This branch replaces the
upstream Wine-server helper's pre-existing archive requirement with a complete
48-object source build. All three Wine archives have passed CI; full LLVM/DXMT
and final app linking remain under validation. Runtime DLLs supplied by the user
are hash-pinned for local assembly, with no DLL bytes committed to Git.
Do not represent the separate upstream Madeira baseline IPA as SM-002.

### Performance targets vs verified results

The built-in Madeira runtime already exposes a 30/40/60/display-max/RAW
presentation selection. A 30 FPS symptom may be a game limiter, a configured
presentation cap, or an emulator CPU/GPU bottleneck; benchmark those separately.
An iPhone panel supporting 120 Hz cannot *display* 200 unique frames/second.
No Borderlands 1 >30, Cuphead >200 or 120 FPS claim is made without repeatable
on-device tests.

### Compatibility and achievements

The patched code does **not** add working EA App, Ubisoft Connect, Epic Online
Services, Steam achievements, or anti-cheat support. Real launcher compatibility
requires installer/runtime/network/TLS/process tests in the corresponding Wine
prefix, and some DRM/kernel drivers will remain unsupported. Steam achievement
handling must use Valve's authenticated Steam client/Steamworks callbacks and
the game's own entitlement; no offline fake unlocks are injected.

## Native-engine changes

- **DirectX 9 / DXMT**: `src/d3d9/d3d9_multithread.hpp` gets an owner-thread recursion fast path. It avoids an unnecessary atomic read/modify/write when the current thread already owns the D3D9 lock. The original acquire-CAS remains for first acquisition and cross-thread contention; optimization only applies to the Madeira build.
- **Wine / iOS input dispatch**: `app/Madeira/Winios/Winios.m` removes mandatory synchronous per-event `stderr` logging (set `MADEIRA_INPUT_TRACE=1` to restore trace output) and drains a bounded batch of 64 events per mutex hold, dispatching them outside the mutex. All mouse and key events retain FIFO order, with no movement coalescing.
- **No game-specific INI changes**, no modification of installed Steam games, no dummy FPS improvements.

These are plausible improvements to emulation-side CPU/latency overhead, not yet demonstrated FPS gains. In particular, they do **not** establish whether Borderlands GOTY's 30 FPS is a limiter, FEX/WoW64 bottleneck, or DirectX9 GPU/present path bottleneck.

## Apply to separate Madeira / DXMT checkout

```sh
python3 SteamMobile/tools/patch_native_engine.py --madeira /path/to/Madeira --dxmt /path/to/dxmt --check
python3 SteamMobile/tools/patch_native_engine.py --madeira /path/to/Madeira --dxmt /path/to/dxmt --apply
```

Run only on a disposable working copy of Madeira (with the matching DXMT `ios-port` sources). The script refuses unexpected changes and writes `.steam-mobile-sm001.bak` backups before editing. To roll back, restore both backups.

GitHub Actions runs deterministic source checks and a four-thread C++ test using the actual DXMT header. It **does not** perform an iOS build or test on iPhone hardware.

## Next engine-specific benchmarks

Compare an identical 60-second mission across builds and repeats, with identical device thermal state, game mode, rendering resolution and FPS mode. Measure rendered FPS, p1 frame times, GPU load, CPU load, DX9 lock contention and input latency. Test both uncapped and display-max modes. For Borderlands DX9/WoW64, sample 32-bit FEX translation and the D3D9 present/command-queue path before enabling experimental performance hacks universally.

## Why no IPA yet

Madeira's `docs/BUILDING.md` documents missing unpushed submodule commits and extra native toolchains, licensed binaries, Xcode dependencies and signing. A public clean checkout currently does not fully reproduce the maintainer's working application. This GitHub repo already hosts a different iOS project; simply invoking its existing `build-milazy.yml` cannot produce a Madeira-based Steam Mobile IPA.

**Steam achievements:** an authenticated read-only CM reader and account-scoped notification history are implemented but require account/device verification. Gameplay unlock writes and offline reconciliation are not implemented. See `docs/GAMENATIVE_PORT.md`.

**Measurements:** Performance Lab capture and comparison tooling are described in `docs/DEVICE_BENCHMARKS.md`; no device results are claimed.

**Icon:** the generator now uses versioned Steam and Apple vector paths for the requested personal design. See `assets/brand/README.md` for provenance and the unresolved public-branding permission requirement.

Upstream references:
- Madeira main pinned: `48f976429c189f8396e23d251d8a82f43c705922`
- DXMT ios-port pinned: `db546ee466ad50ec6463edb5fa183de11db43761`
