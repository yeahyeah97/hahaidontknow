# v0.4.0 build 7: foreground direct G2 captions

The existing CoreBluetooth connection/auth and teleprompter proof path remain.
LEFT audio notifications use UUID 00002760-08C2-11E1-9073-0E8AC72E6402.
Start requires verified RIGHT protocol response, both command channels and
confirmed LEFT audio notification subscription.

EvenAI CTRL uses service 07-20 and the existing global message counter:
08 01 10 <msgId> 1A 02 08 02 (ENTER), or final byte 03 (EXIT).
The same lifecycle payload goes to both lenses through the existing 0xAA
frame, CRC and transport sequence allocation. No ASK/cloud request is sent.

Exactly 205 bytes are accepted. The first 200 bytes contain five 40-byte
10-ms LC3 frames. Bytes 200-203 are ignored; byte 204 is a wrapping sequence
number. Duplicates are dropped and gaps counted. liblc3 decodes at 16 kHz mono,
signed Int16, into 800 samples / 1600 little-endian bytes per packet.

Each decoded packet immediately reaches appendPCM16. Kroko loads only on first
caption activation. Audio received while the model loads is dropped, not buffered.
The inference queue holds at most two packets; overload drops are counted.
Partial results reach the app/HUD without waiting for endpoints.

Caption HUD initialization uses the existing teleprompter sequence (about 2.6s);
after that, updates reuse page 0 and the existing sync command. Partial requests
are throttled to 120 ms, final requests bypass the throttle. Physical validation
of incremental page refresh and coexistence with EvenAI remains necessary.
The five-second HUD clear retains the in-memory transcript.

Stop sends EXIT, rejects subsequent audio, frees decoder state and invalidates
recognizer callbacks. Backgrounding stops this foreground milestone.
No audio or transcript logging/persistence is introduced; diagnostics are numeric.
MIC ACTIVE requires a valid packet, PCM ACTIVE a successful frame decode and
ASR LIVE a nonempty partial/final result.

## Hardware acceptance (not proven by CI)
1. Launch; connect both G2 lenses; run the existing direct HUD test.
2. Start captions; observe MIC OPEN and 6402 LEFT NOTIFY ON.
3. Confirm 205-byte packet count, sequence, successful frames and moving LEVEL.
4. Speak Italian; confirm partial text in app and physical glasses.
5. Stop; verify EXIT and no subsequent accepted audio.
6. Repeat start/stop, disconnect/reconnect and background/foreground.
