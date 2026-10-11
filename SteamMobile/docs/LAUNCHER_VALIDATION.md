# Launcher and anti-cheat validation

Reviewed 2026-10-10. No launcher installation, account login or game handoff
has been tested on the target iPhone. Importing an EXE is an existing Wine
entry point; it is not a launcher compatibility result.

| Component | Installer | Login/session persistence | Game handoff | Current evidence |
|---|---|---|---|---|
| EA App | NOT TESTED | NOT TESTED | NOT TESTED | Official Windows client requires Windows 10/11 x64 |
| Epic Games Launcher | NOT TESTED | NOT TESTED | NOT TESTED | No device result |
| Ubisoft Connect | NOT TESTED | NOT TESTED | NOT TESTED | No device result |
| GOG Galaxy | NOT TESTED | NOT TESTED | NOT TESTED | No device result |
| Battle.net | NOT TESTED | NOT TESTED | NOT TESTED | No device result |
| Madeira Dock / Steam client | NOT TESTED | NOT TESTED | NOT TESTED | Existing upstream integration retained |
| EA Javelin Windows driver | BLOCKED | Not applicable | BLOCKED for titles requiring it | Requires facilities outside this iOS user-process runtime |

## EA evidence and limitation

EA's current [Javelin support article](https://help.ea.com/en/articles/platforms/pc-ea-anticheat/)
requires Windows 10 20H1 or newer and says protected games cannot run with the
anti-cheat removed. Its linked [technical explanation](https://www.ea.com/security/news/eaac-deep-dive)
describes a kernel-mode driver. The [EA App system requirements](https://www.ea.com/ea-app)
list 64-bit Windows 10/11 for its Windows client.

Engineering conclusion: FEX translates guest user-mode instructions and Wine
implements user-facing Windows APIs; this app does not supply the Windows
kernel, its driver loading environment or Windows boot integrity. An ARM64
Windows driver would still need those facilities. A working installer or
login would not remove that restriction. The reviewed EA materials do not
document a publisher-authorized iOS user-mode path. Future Linux/Proton work
or discussion is not evidence of an available iOS integration.

An EA title without this requirement must still pass its own tests. An
authorized Windows-host option is separate remote execution, not local iPhone
compatibility. No integrity checks or attestations are modified here.

## Test record required for each launcher

Use the publisher's official installer, recording download source, file hash,
version and signature. Run only after the genuine IPA starts correctly and
JIT is verified. Preserve a recoverable prefix before installation.

Record each stage independently: installer launch and exit code; installed
files and required runtimes; child-process startup; WebView/browser login and
callback; legitimate account library; restart/session persistence; title
ownership; download/verification; launcher-to-game handoff; gameplay.

Attach timestamped Wine logs and the build manifest. Record TLS/certificate,
service, registry, .NET/VC-runtime and subprocess failures by exact error.
Do not include credentials, cookies, authorization URLs or pairing PINs in
shared logs. A clean close or zero installer exit code alone is insufficient
to mark later stages PASS. A device harness with automated stage observation
remains to be implemented; this document is a test protocol, not that harness.
