#!/usr/bin/env python3
"""Port GameNative's account-backed achievement fetch to Madeira's Swift Steam CM.

Sources:
  https://github.com/utkarshdalal/GameNative (GPL-3.0)
  app/src/main/java/app/gamenative/service/SteamService.kt
  app/src/main/java/app/gamenative/statsgen/{VdfParser,StatsAchievementsGenerator}.kt

Uses the EXISTING authenticated Steam CM session, not an embedded Web API key
or a second competing login. This phase intentionally performs read-only Steam
queries; writing unverified local JSON states to a user's account is forbidden.
"""
from pathlib import Path
import argparse


def once(s: str, old: str, new: str, name: str) -> str:
    n = s.count(old)
    if n != 1:
        raise ValueError(f"{name}: expected one upstream anchor, got {n}")
    return s.replace(old, new, 1)


STEAM_READ = r'''
// Steam Mobile: account-backed achievements, ported from GameNative's reader.
// GPL-3.0; see SteamMobile/docs/GAMENATIVE_PORT.md.
// Not an achievement generator, fake unlocker, or publisher stats writer.
struct SteamMobileAchievement: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let unlocked: Bool
    let unlockTimestamp: UInt32
    let hidden: Bool
}

enum SteamMobileAchievementError: LocalizedError {
    case notSignedIn, gameSessionRunning, invalidResponse, noSchema
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to your Steam account first."
        case .gameSessionRunning: return "Steam statistics refresh after the game closes. Valve's game client currently owns this account session."
        case .invalidResponse: return "Steam rejected or returned an invalid achievement response. Retry later."
        case .noSchema: return "This game has no available achievement schema, or Steam did not return one."
        }
    }
}

/// Strict subset of Valve's *binary* KeyValues format (different from SteamKeyValues
/// text VDF reader). Bounded recursion, byte count, entries, and string length.
private struct SteamMobileBinaryVDF {
    indirect enum Value {
        case section([String: Value]), text(String), number(Int64)
        var fields: [String: Value] {
            guard case .section(let value) = self else { return [:] }
            return value
        }
        var string: String {
            switch self {
            case .text(let s): return s
            case .number(let n): return String(n)
            default: return ""
            }
        }
    }
    private let data: [UInt8]
    private var offset = 0
    private var entries = 0

    init(_ bytes: Data) throws {
        guard bytes.count > 0, bytes.count <= 4 * 1024 * 1024 else {
            throw SteamMobileAchievementError.invalidResponse
        }
        data = Array(bytes)
    }

    mutating func readCString() throws -> String {
        let start = offset
        while offset < data.count && data[offset] != 0 {
            offset += 1
            if offset - start > 32768 { throw SteamMobileAchievementError.invalidResponse }
        }
        guard offset < data.count else { throw SteamMobileAchievementError.invalidResponse }
        let bytes = data[start..<offset]
        offset += 1
        return String(decoding: bytes, as: UTF8.self)
    }

    mutating func readUInt(_ length: Int) throws -> UInt64 {
        guard length > 0, length <= 8, offset <= data.count - length else {
            throw SteamMobileAchievementError.invalidResponse
        }
        var result: UInt64 = 0
        for i in 0..<length { result |= UInt64(data[offset + i]) << (8 * i) }
        offset += length
        return result
    }

    mutating func section(depth: Int = 0) throws -> [String: Value] {
        guard depth <= 14 else { throw SteamMobileAchievementError.invalidResponse }
        var out: [String: Value] = [:]
        while offset < data.count {
            let kind = data[offset]
            offset += 1
            if kind == 8 { return out }
            entries += 1
            guard entries <= 50000 else { throw SteamMobileAchievementError.invalidResponse }
            let key = try readCString().lowercased()
            switch kind {
            case 0: out[key] = .section(try section(depth: depth + 1))
            case 1: out[key] = .text(try readCString())
            case 2: out[key] = .number(Int64(Int32(bitPattern: UInt32(try readUInt(4)))))
            case 3: out[key] = .number(Int64(try readUInt(4))) // float unused in achievements
            case 7, 10: out[key] = .number(Int64(bitPattern: try readUInt(8)))
            default: throw SteamMobileAchievementError.invalidResponse
            }
        }
        throw SteamMobileAchievementError.invalidResponse
    }
}

enum SteamMobileAchievementReader {
    /// CMsgClientGetUserStatsResponse, Valve EMsg 819.
    static func parse(_ bytes: Data, appID: Int) throws -> [SteamMobileAchievement] {
        var decoder = ProtobufDecoder(bytes)
        var resultCode: Int32 = 2
        var schema = Data()
        var blocks: [UInt32: [UInt32]] = [:]
        var reportedApp: UInt64 = 0
        while let tag = try decoder.readTag() {
            switch (tag.fieldNumber, tag.wireType) {
            case (1, .fixed64):
                reportedApp = try decoder.readFixed64()
            case (2, .varint):
                resultCode = Int32(truncatingIfNeeded: try decoder.readVarint())
            case (4, .lengthDelimited):
                schema = try decoder.readBytes()
            case (6, .lengthDelimited):
                var block = ProtobufDecoder(try decoder.readBytes())
                var blockID: UInt32?
                var times: [UInt32] = []
                while let field = try block.readTag() {
                    switch (field.fieldNumber, field.wireType) {
                    case (1, .varint): blockID = UInt32(truncatingIfNeeded: try block.readVarint())
                    case (2, .fixed32): times.append(try block.readFixed32())
                    case (2, .lengthDelimited):
                        // packed fixed32 repeated unlock_time, if used by the server
                        let packed = try block.readBytes()
                        guard packed.count % 4 == 0, packed.count <= 4096 else {
                            throw SteamMobileAchievementError.invalidResponse
                        }
                        var nested = ProtobufDecoder(packed)
                        while !nested.isAtEnd { times.append(try nested.readFixed32()) }
                    default: try block.skip(wireType: field.wireType)
                    }
                }
                if let blockID { blocks[blockID] = times }
            default: try decoder.skip(wireType: tag.wireType)
            }
        }
        guard resultCode == 1, reportedApp == UInt64(appID) else {
            throw SteamMobileAchievementError.invalidResponse
        }
        guard !schema.isEmpty else { throw SteamMobileAchievementError.noSchema }
        var binary = try SteamMobileBinaryVDF(schema)
        let parsed = try binary.section()
        var found: [SteamMobileAchievement] = []
        var seen = Set<String>()
        for (_, root) in parsed {
            for (idText, stat) in root.fields["stats"]?.fields ?? [:] {
                guard let blockID = UInt32(idText),
                      let bits = stat.fields["bits"] else { continue }
                for (bitText, candidate) in bits.fields {
                    guard let index = Int(bitText), index >= 0, index <= 4096 else { continue }
                    let fields = candidate.fields
                    let name = fields["name"]?.string ?? ""
                    guard !name.isEmpty, !seen.contains(name) else { continue }
                    seen.insert(name)
                    let display = fields["display"]?.fields ?? [:]
                    func local(_ key: String) -> String {
                        guard let field = display[key] else { return "" }
                        return field.fields["english"]?.string
                            ?? field.fields["en"]?.string
                            ?? field.string
                    }
                    let timestamp = (blocks[blockID].flatMap {
                        index < $0.count ? $0[index] : nil
                    }) ?? 0
                    found.append(SteamMobileAchievement(
                        id: name,
                        title: local("name").isEmpty ? name : local("name"),
                        detail: local("desc"),
                        unlocked: timestamp != 0,
                        unlockTimestamp: timestamp,
                        hidden: display["hidden"]?.string == "1"
                    ))
                }
            }
        }
        return found.sorted {
            if $0.unlocked != $1.unlocked { return $0.unlocked && !$1.unlocked }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
}
'''

STEAM_METHOD = r'''
    /// Reads Valve's real achievement state using Madeira's logged-in CM session.
    /// Never open a second login while Dock / a game runs: account handover wins.
    func steamMobileAchievements(for appID: Int) async throws -> [SteamMobileAchievement] {
        guard SteamSignIn.isSignedIn else { throw SteamMobileAchievementError.notSignedIn }
        guard appID > 0, appID <= Int(UInt32.max) else {
            throw SteamMobileAchievementError.invalidResponse
        }
        guard !inSession && gate.open && !gate.heldForDock else {
            throw SteamMobileAchievementError.gameSessionRunning
        }
        try await session.ensureConnected()
        let steamID = session.steamID
        guard steamID != 0 else { throw SteamMobileAchievementError.notSignedIn }
        var request = ProtobufEncoder()
        request.writeFixed64(fieldNumber: 1, value: UInt64(appID)) // game_id
        request.writeFixed64(fieldNumber: 4, value: steamID)        // steam_id_for_user
        let answer = try await session.sendAndWait(
            eMsg: .clientGetUserStats, body: request.data,
            responseEMsg: .clientGetUserStatsResponse, timeout: 20
        )
        return try SteamMobileAchievementReader.parse(answer.body, appID: appID)
    }
'''

def patch(madeira: Path) -> None:
    proto = madeira / "app/Madeira/SwiftSteam/Core/SteamProtocol.swift"
    model = madeira / "app/Madeira/SteamOwnedLibrary.swift"
    p = proto.read_text()
    p = once(p, '    case clientLicenseList = 780',
             '    case clientLicenseList = 780\n    case clientGetUserStats = 818\n    case clientGetUserStatsResponse = 819',
             "Steam EMsg achievements")
    m = model.read_text()
    m = once(m, '    private let session = SteamSession()',
             STEAM_METHOD + '\n    private let session = SteamSession()',
             "Steam account stats session")
    m += '\n' + STEAM_READ
    proto.write_text(p)
    model.write_text(m)

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--madeira", required=True, type=Path)
    args = ap.parse_args()
    patch(args.madeira)
    print("GameNative-inspired authenticated Steam achievements reader integrated")
