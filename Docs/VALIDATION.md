# Milazy 3.1.1 validation

## Automated checks
The main workflow compiles and runs Foundation/CoreGraphics regression checks,
builds the Release unsigned device app, validates the embedded keyboard extension
and keyboard-service metadata, then uploads the unsigned IPA. The workflow prints
its Xcode/SDK versions so the build environment is explicit.

The local Space path has no UITextChecker, recognizer, network, persistent write,
or wait for a prediction. It uses dictionary lookups and a bounded edit index.
An optimized CI sample of 1000 local decisions completed in about 0.0042 seconds
on the macOS runner. This is a model microbenchmark, not end-to-end iPhone latency.

Predictions and learning run on one worker. A typed word valid in either language
is protected in Auto mode once checked. Names, supplementary lexicon entries,
repeatedly kept words and correction undo are protected. Only selected suggestions
teach source-to-replacement mappings. The original word remains selectable.

## Physical-device acceptance checks still required
Use the iPhone 17 Pro Max with the requested iOS version. Test Messages, WhatsApp
and Discord, in light/dark modes and narrow/short keyboard bounds.

- Type rapidly, overlapping fingers; release an earlier key after typing another.
  No last-character replacement should occur on release.
- Compare displayed capitals and inserted letters at field start, after punctuation,
  quotes, line breaks, deletion, manual Shift and double-tap caps lock. Include a
  host field using capitalization None, Words and All Characters.
- Type "teh " and "perche " immediately, before predictions settle. Check "the "
  and "perché ". Backspace immediately afterward restores the original word.
- Mix "ciao hello", "don't", "l'amico", names and slang. Pick the original word
  repeatedly and confirm it stays unchanged after restarting the keyboard.
- Check Auto, IT and EN modes, every layout/hitbox option, popup/haptic/sound toggles.
- Verify the prediction row stays above keys, tools scroll without overlap, all
  clipboard history is accessible, and iOS retains its own globe/microphone area.
- Run Deaf AI on grammatical text and the fragmented examples in the audit.
  Review subjects, targets, hopes/fears, negation, conditions and event status.
- Change the selected text, cursor, document or input while AI is running.
  An old result must not replace the new text.
- Verify configured Tenor/GIPHY providers and clipboard paste with Full Access.

AI semantic quality and live GIF requests are not claimed as validated without
provider credentials. AI routing is heuristic; semantic outputs still need review.
The available workflow uses Xcode 16.4 / iOS 18.5 SDK, not an iOS 27 SDK.

