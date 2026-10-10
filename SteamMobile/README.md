# Steam Mobile — experimental native engine (SM-001)

This is an isolated development workspace in the **steam-mobile-engine-sm001** branch of `beamerwz/iphone`. The existing MilazyKeyboard app on `main` is unchanged. This is **not a compiled IPA**.

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

**No native Steam achievement implementation yet.** Correct Steam achievements require verified Steamworks state/events through Valve's original client and synchronization. The performance patch neither implements nor fakes them.

Upstream references:
- Madeira main pinned: `48f976429c189f8396e23d251d8a82f43c705922`
- DXMT ios-port pinned: `db546ee466ad50ec6463edb5fa183de11db43761`
