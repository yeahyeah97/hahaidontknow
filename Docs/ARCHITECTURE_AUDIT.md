# Milazy architecture audit

Baseline: main at baabbeba33d4a1b4fa67a88c85371949b3dd46f4.
All changes use independent public-API models. No experimental branch content is used.

The baseline contains an approximately 1,600-line KeyboardViewController handling
input, predictions, language detection, touch resolution, presentation and tools.
Shared services cover AI, GIF, preferences, clipboard, touch and personal vocabulary.

## Findings before implementation
- TouchKey persists Gaussian samples before UIButton sends touchDown.
- Space executes UITextChecker, language recognition and dictionary persistence.
- Prediction work reads mutable personal dictionaries concurrently with main-thread writes.
- Predictions privilege one language and can correct a valid word in the other language.
- Language recognition is stateless and frequently changes on tiny context differences.
- Release correction deletes the last character without checking which touch inserted it.
- Shift state updates and deferred title updates can disagree. Manual shift is overwritten.
- Fixed canvas height and unbounded tool stack can conflict with short host layouts.
- AI completion deletes captured context without validating whether the document changed.
- Semantic Fix already has useful role/scope prompts; short grammatical sentences unnecessarily use two requests.

## Incremental approach
1. Preserve touch-down insertion; defer feedback/learning, unify bounded touch scoring,
   remove release replacement, unify rendered capitalization and insertion.
2. Extract serial bilingual prediction with language hysteresis and an indexed local
   Space decision; learn user-confirmed choices, support correction undo and protect names.
3. Make layout respond to available height, scroll tools, validate AI context before applying,
   and preserve opt-in semantic processing and existing clipboard/emoji/GIF/settings.

GitHub Actions compiles the unsigned device app and runs portable regression checks.
Physical-device typing latency and host layouts require testing on the user's iPhone.
The runner reports its actual Xcode/SDK; an iOS 27 claim requires an iOS 27 SDK/device.
