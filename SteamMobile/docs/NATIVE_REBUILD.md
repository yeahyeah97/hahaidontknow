# Native rebuild investigation — 2026-10-10

## Evidence and source identity

The previous [IPA run 38054275610](https://github.com/yeahyeah97/hahaidontknow/actions/runs/38054275610),
at `599519497353139f6db17b2e35a4bda9d6089a48`, compiled FEX, FFmpeg,
Rust pairing and the app's Swift sources. Its diagnostic Xcode build exited 65
at linking; the subsequent required-input gate explicitly failed for all four
Wine/DXMT archives and the Microsoft CRT directory. No optimized IPA resulted.

The original release has only an IPA and a checksum asset, not a native archive
SDK or complete build-provenance manifest. These are **source tag pins**, not
independent proof of what the author's local linker put into the release:

| Component | Madeira v0.1.3 source tag | Current Steam Mobile locked source |
|---|---|---|
| Madeira | `4e9d45a74294cd820120791c4b3f2b79adf4fc70` | `48f976429c189f8396e23d251d8a82f43c705922` |
| FEX | `26859e184ad90f0e811d7f8bbd943a4b1573a2c3` | `3bec2ac498bf78156ab47c0c194b0e8cb2849756` |
| Wine | `4f5b19718f4de88ecc5cb0dc08b119497a67ba8f` | `257f271cfffed9f22f7987cac53bc00095d092fe` |
| DXMT | `35a4db11bd1bda380c5176a3bc6c1878f7192101` | `db546ee466ad50ec6463edb5fa183de11db43761` |
| Madeira Dock | `3cadfbea700e4da4b04e331dd7ef1ba633dfacef` | Not rebuilt in the first native dependency pass |
| LLVM | Documented `8dfdcc7b7` | Resolved to `8dfdcc7b7bf66834a761bd8de445840ef68e4d1a` (LLVM 15.0.7 lineage) |
| FreeType | Documented 2.13.3 | `42608f77f20749dd6ddc9e0536788eaad70ea4b5` |
| FFmpeg | Source archive 7.1.1 | Same pinned archive; SHA-256 `733984395e0dbbe5c046abda2dc49a5544e7e0e1e2366bba849222ae9e3a03b1` |
| Rust | Compiler version not recorded in original release | Cargo.lock preserved; actual runner compiler recorded in new manifest, not yet pinned |

Sources: [v0.1.3 tree](https://github.com/willfaust/Madeira/tree/v0.1.3),
[upstream build record](https://github.com/willfaust/Madeira/blob/48f976429c189f8396e23d251d8a82f43c705922/docs/BUILDING.md),
[DXMT recipe](https://github.com/willfaust/Madeira/blob/48f976429c189f8396e23d251d8a82f43c705922/build/dxmt-ios/README.md).

## Implemented build changes

- `dependencies.lock.json` is the source of exact Git revisions. Fetch verifies
  the Wine, DXMT and FEX pins against Madeira's gitlinks. Required nested
  submodules use those repositories' own pins.
- Generate Wine `config.h` and IDL headers with native macOS tools; iOS archives
  compile against them using the upstream iPhone SDK flags and iOS shims.
- Build GnuTLS/GMP/Nettle and FreeType with their matching headers. Verify the
  crypto source tarballs before compilation. FFmpeg is built before ntdll.
- Compile all 48 Wine server objects: each module from `server/Makefile.in`,
  the existing iOS replacements, and the upstream auxiliary objects. Preserve
  the complete symbol-renaming pass. No base archive or old object is needed.
- Stop ntdll compilation on any failed source, before archiving.
- Build host llvm-tblgen, then iOS LLVM libraries. Apply the documented LLVM
  Darwin/iOS linker rule. Combine DXMT and LLVM using Apple's libtool, including
  the patched native D3D9 frontend, and stage the resulting archive for Xcode.
- Record source SHAs, applied source-diff hashes, archive and guest DLL hashes,
  and actual Xcode/clang/Rust/CMake/SDK versions. Preserve compiler diagnostics
  and applied patches as a separate Actions artifact.
- A failed Wine or DXMT step still fails the final release gate even if an
  archive happens to exist. Independent dependency builds can collect errors
  in one run. Follow-up pushes no longer cancel an active native build.

These recipes require successful macOS CI validation before being called a
reproducible build. The first run is
[38055570349](https://github.com/yeahyeah97/hahaidontknow/actions/runs/38055570349).
It built all three Wine archives successfully. LLVM failed because static-only
CMake probes falsely accepted librt; the fix uses executable linker probes and
builds only `llvm-libraries`. The Xcode log additionally identified the omitted
FEX `JemallocLibs` allocator-hooks target, which exists even with the optional
FEX allocator disabled. Both fixes require a subsequent native CI run.
The accompanying [host tests passed](https://github.com/yeahyeah97/hahaidontknow/actions/runs/38055573832).

## Remaining package inputs and validation

The user supplied 12 distinct Microsoft-signed x64 runtime DLLs, version
14.51.36247.0; the extra vcruntime140_1 filename is byte-identical. Windows
Authenticode and structural PE checks passed. `runtime-inputs.lock.json`
records their exact hashes; DLL bytes stay local.

After Wine, DXMT and Xcode linking succeed, CI exports a clearly labelled
app build input, its source/run identity, native binary hashes and linker maps.
`assemble_local_ipa.py` checks that artifact against the expected commit and
archive hash, adds the locally supplied hash-pinned DLLs, repacks matching
identifiers and runs the full final IPA verifier. This route does not publish
the user's runtime DLLs in Git source. The existing online release gate still
rejects absent CRT inputs. Neither an incomplete app nor a diagnostic build
is presented as a complete IPA.

The first native pass retains upstream committed PE modules and other bundled
libraries. Their hashes are recorded; they must not be described as freshly
rebuilt. A fully source-rebuilt guest farm, pinned Rust compiler and stable host
toolchain inputs remain additional work. An input manifest alone does not prove
that every archive member was linked; final binary inspection and linker evidence
must accompany a release manifest.

Use Debug for the app, as upstream documents guest crashes in Release. Native
FEX/LLVM and Wine/DXMT still use their optimized upstream compiler settings.
Do not change this app setting merely to obtain a more attractive build label.

Signing is separate: match the main/helper bundle IDs and background task IDs,
re-sign the app, extension and frameworks with the user's permitted provisioning
profile, and verify the resulting entitlements. Upstream requests `get-task-allow`,
`com.apple.security.cs.allow-jit` and increased-memory-limit; their presence in a
source plist is not proof that a signing service or device grants them. Device
pairing, debugger attachment and actual executable JIT memory still need testing.

## Performance investigation finding

DXMT's `ios_frame_*` declarations describe a rich diagnostic instrument, but the
current public Madeira source implements them as no-ops in
`build/ntdll-unix/virtual_ios.c`, with `ios_frame_stats_on = 0`. Enabling a setting
cannot make these hooks report GPU times or frame-time distributions. The live
present counter is real, but a 100 ms counter sample cannot yield individual
frame times or valid 1% lows. Performance Lab needs real sample collection and
explicitly identified rendering paths before such metrics can be displayed.

No game, sustained FPS, launcher login, Steam achievement write, device signing
or iPhone JIT result has been established by these host tests.
