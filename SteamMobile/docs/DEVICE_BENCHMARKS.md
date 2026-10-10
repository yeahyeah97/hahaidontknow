# Device benchmark capture

Status: capture implementation added; comparison arithmetic host-tested;
iOS compilation and real device measurements pending. No FPS improvement is claimed.

Performance Lab can record 2, 10 or 30 minutes while gameplay runs in the app.
Enter the game, save/scene, resolution, settings and observed renderer in its
label. Start capture, enter the chosen scene, then return to export the JSON.
Reports remain in Documents/PerformanceReports. The report records its source
commit when stamped by the native workflow.

The one-second sampler reads the existing native DXMT present counter, process
physical memory footprint, thermal state, Low Power Mode, presentation mode
and existing JIT-helper readiness. Timer work runs on the main queue, outside
the renderer; collection is opt-in and bounded. Scheduling delays and counter
resets are explicit. The report labels helper readiness as a helper check,
not independent proof of executing JIT code.

This counter includes RAW skipped presents and can aggregate swapchains.
It does not measure displayed frames or identify a game's DirectX version.
An uninstrumented renderer can leave it at zero. No individual frame times,
stutter distribution, 1% lows, shader-cache hits, FEX translation statistics,
CPU bottleneck attribution or GPU utilization are derived from timer samples.
Those need additional native instrumentation and overhead validation.

## Repeatable device protocol

1. Use the same device, iOS version, game build, save, scene, resolution,
   Wine prefix and graphics settings. Record the renderer using runtime
   evidence, not the game's name. Keep power source and screen recording
   settings consistent; record Low Power Mode.
2. First establish installation, launch and actual JIT operation. Keep a
   recovery copy of the working baseline and saves.
3. Warm the same scene and shader cache, then replay the same route. Collect
   at least three matched runs per build, alternating the order. Use separate
   recordings for startup, menus, steady gameplay and heavy action.
4. Run a 30-minute session for thermal/memory behavior. Note crashes, artifacts,
   audio/input regressions and any renderer or pacing changes.
5. Export both JSON files and retain the native build provenance alongside them.
   A stock upstream app lacks this capture UI; a baseline must be built with
   the same instrumentation before making matched comparisons.

Run `python SteamMobile/tools/compare_captures.py baseline.json candidate.json`.
The tool computes elapsed-time-weighted aggregate present throughput and peak
sampled memory. It excludes inactive, delayed and reset intervals, reports
coverage, and suppresses percentage comparisons when labels, pacing, thermal
conditions or Low Power Mode differ, or fewer than 30 seconds are usable.
Matching labels do not establish identical gameplay: inspect the traces.

Borderlands 1 and Cuphead have **NOT TESTED** status. The user's reported
Borderlands result is a target for investigation, not data produced by this
tool. Controller latency requires an independent input-to-display measurement;
neither present throughput nor a lock microbenchmark supplies it.
