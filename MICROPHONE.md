# v0.4.1 build 8: G2 microphone reception and recovery

Physical v0.4.0 testing proved application launch, discovery, both GATT command
channels, RIGHT 5402 protocol verification and LEFT 6402 notification
subscription. It did not prove that a 6402 value notification or microphone
audio arrived. v0.4.1 focuses on making that boundary observable and recoverable.
The existing HUD/display implementation and downstream LC3/ASR pipeline are
unchanged.

## Microphone control

EvenAI CTRL uses service 07-20 through the existing 0xAA framing, CRC and
transport counters. Each lens now receives a distinct global message ID:

- ENTER: 08 01 10 <msgId> 1A 02 08 02
- EXIT: 08 01 10 <msgId> 1A 02 08 03

The app logs ENTER/EXIT TX separately for L and R. Incoming 07-20 traffic logs
its side, service and parsed protobuf message ID. A response whose message ID
matches one of the pending ENTER IDs is reported as an ACK. A two-second timer
reports when no matching response arrives. An ACK never marks the microphone
active; only a real valid LEFT 6402 packet does.

## 6402 observation

Every LEFT 6402 value notification is counted before session/open gating. Logs
contain metadata only: total number, size, validity and the byte-204 sequence
counter. The UI exposes total, valid 205-byte and invalid-size counts. Audio
bytes, PCM and speech are never logged or persisted.

Only a 205-byte notification received while the user still wants microphone
audio is forwarded to the existing decoder. The decoder continues to split the
first 200 bytes into five 40-byte LC3 frames and produce 800 signed PCM16
samples. MIC ACTIVE requires a valid packet, PCM ACTIVE a successful decode,
and LEVEL is calculated from decoded PCM.

## Recovery

User intent and per-connection state are separate. A disconnect clears the
current ENTER/open state and decoder evidence but preserves the user's active
caption/microphone choice. Stale peripherals and characteristics are removed.
Recovery rescans after bounded delays of 0.5, 1, 2, 4 and then 5 seconds.

An eight-second scan watchdog recovers when both usable command channels are
not available. A five-second protocol watchdog resets the RIGHT session if no
verifying RIGHT 5402 response appears. Bluetooth powered-off state clears all
connection-specific objects; powered-on automatically starts a fresh scan.
After both command channels, RIGHT verification and LEFT notification
subscription return, ENTER is automatically sent again if the user still wants
the microphone.

## Remaining protocol assumptions

The 6402 UUID, 205-byte layout and LC3 parameters come from public reference
implementations but still require a real incoming packet on this hardware.
The ACK classifier assumes a 07-20 response echoes the ENTER protobuf message
ID. All 07-20 responses are logged even when that assumption does not hold, so
the next device run can distinguish no response from an unmatched response.

## Hardware acceptance

1. Launch, connect both lenses and confirm LINK VERIFIED.
2. Start captions and inspect separate ENTER TX lines for L and R.
3. Check whether MIC CTRL reaches ACK or NO RESPONSE.
4. Check whether 6402 RX increments and whether packets are 205B or BAD.
5. Speak and confirm MIC ACTIVE, PCM ACTIVE and LEVEL above 0.000.
6. Interrupt either lens and confirm RECOVERING, rescans, protocol restoration
   and automatic ENTER without toggling iPhone Bluetooth.
7. Stop and confirm separate EXIT TX lines for L and R.


