# Third-party components

Google liblc3 v1.1.3, commit 96a3af0beb5487aca3b98a4b992a539a1f6d80d1,
https://github.com/google/liblc3, Apache-2.0.
The workflow fetches this exact source revision without modifications and retains
its source copyright headers. A generated compile-time namespace isolates all
lc3_* identifiers from the LC3 copy already bundled in Mentra. LICENSE and NOTICE (when present) are copied into
the app's bundled Resources/Licenses directory.

The Swift/C bridge and packet integration are independently written for this app.
Protocol facts were checked against these public ffs-os references:
- https://github.com/yonif8/ffs-os/blob/main/legacy/sdk/mic.ts
- https://github.com/yonif8/ffs-os/blob/main/modules/ffs-ble/ios/G2Protocol.swift
- https://github.com/yonif8/ffs-os/blob/main/modules/ffs-ble/ios/G2Central.swift
- https://github.com/yonif8/ffs-os/blob/main/apple/FFSBridge/Core/LC3Bridge.c

No ffs-os implementation code is vendored.
