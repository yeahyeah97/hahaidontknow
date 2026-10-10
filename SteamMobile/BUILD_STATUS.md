# Steam Mobile — current build status (2026-10-10)

## Current engineering pass

Source changes are on PR #2, starting with commit
`e82112f4f2ed38fbfd7616064df8ebfe83829cb2`. The prior native pipeline never
built the four missing Wine/DXMT archives. It now attempts complete Wine-server
compilation, generated Wine headers, crypto/font dependencies, host/iOS LLVM,
and DXMT archive combination from locked source revisions.

- **PASS:** [host CI 38055573832](https://github.com/yeahyeah97/hahaidontknow/actions/runs/38055573832).
- **PASS:** all three Wine archives built from source in [macOS run 38055570349](https://github.com/yeahyeah97/hahaidontknow/actions/runs/38055570349).
- **FAILED:** iOS LLVM linked an unavailable `rt` library after static-only CMake probes falsely detected it. Xcode also exposed the omitted FEX `JemallocLibs` target. Fixes await the next native run.
- **READY LOCALLY:** 12 distinct Microsoft-signed x64 CRT DLLs, all version 14.51.36247.0, supplied by the user and pinned by hash. CI exports the successfully linked app as a build input; local assembly inserts these DLLs and runs the unchanged final package gate.
- **NOT TESTED:** device installation, startup, JIT activation, account login,
  game performance, achievement writes, launcher installation/login/gameplay,
  thermal stability and sustained input latency.

See [NATIVE_REBUILD.md](docs/NATIVE_REBUILD.md) for source-tag identities,
exact source-build changes, provenance limitations and remaining inputs.
No optimized IPA or measured FPS gain has been produced by this pass yet.

## Historical SM-001 record (superseded by the status above)

## What this PR changes

- Runs Madeira's real `build/fex-ios/build.sh` before compiling the iOS app, so CMake generates `FEXCore/Config/ConfigValues.inl` and `ConfigOptions.inl` and compiles the FEXCore archives.
- Checks for the required static libraries and licensed x64 CRT DLLs **before** attempting Xcode compilation. Missing inputs fail with explicit diagnostics rather than generating a misleading IPA.
- Uploads FEX build logs on failure.
- Enables pull-request validation of the existing SM-001 DXMT D3D9 recursive-lock fast path and the Wine/iOS input FIFO patch, without changing those optimizations.

## Last observed failure

GitHub Actions run [38016572590](https://github.com/yeahyeah97/hahaidontknow/actions/runs/38016572590) compiled `FEXBridge.mm` before generating the required FEX config include and stopped at:

```text
fatal error: 'FEXCore/Config/ConfigValues.inl' file not found
```

The pre-build FEX step directly addresses that specific issue. **It does not establish that a complete native build now succeeds.**

## Still missing from upstream public clean checkout

Upstream Madeira's [BUILDING.md](https://github.com/willfaust/Madeira/blob/main/docs/BUILDING.md) documents native outputs that cannot currently be built reproducibly from only the public checkout. These include FEX's matching submodule/toolchains, Wine host archives (including `libwineserver.a`), DXMT's combined iOS archive and LLVM build, FFmpeg iOS libraries, StikJIT/Rust pairing outputs, and Microsoft x64 VC runtime redistributable DLLs.

The workflow checks for the required archives and redistributable DLLs without creating empty substitute files. Obtaining compatible build inputs under their respective licenses and validating a full iPhone build remains separate follow-up work.

## What can be downloaded now

The *baseline* artifact in run 38016572590 is a verified **repackaged Madeira v0.1.3 release**, with a different bundle identifier for sideload signing. It does **not** include the SM-001 DXMT/Wine optimizations.

Only a build that compiles and packages the patched native Madeira engine should be labeled `SteamMobile_Engine_SM001_unsigned.ipa`; this has **not** been demonstrated.

## Scope

- Work isolated to the Steam Mobile feature branch and files under `SteamMobile/` / `.github/workflows/steam-mobile-*`.
- No changes to Milazy, no game INI tweaks, no FPS claims.
- No Steam achievements or DLSS support added.
- A prior local Codex commit `60e6067` exists only on the user's Windows workspace; this GitHub branch is a separate workflow fix and **does not claim to contain that local commit**.
