#!/usr/bin/env python3
"""Strict structural checks for device executables and Windows runtime DLLs.

These checks detect wrong-platform and truncated/placeholder inputs. They do
not replace source provenance, code signing, or runtime correctness tests.
"""
import struct


def device_executable(data, *, dylib=False):
    if len(data) < 4096 or data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Expected a thin 64-bit Mach-O device executable")
    _, cpu, _, kind, count, command_bytes, _, _ = struct.unpack_from("<8I", data)
    if cpu != 0x0100000C or kind != (6 if dylib else 2):
        raise ValueError("Wrong ARM64 Mach-O image type")
    end = 32 + command_bytes
    if not 1 <= count <= 4096 or end > len(data):
        raise ValueError("Invalid Mach-O load-command bounds")
    pos, platform, entry, text_ranges = 32, None, None, []
    dependencies = []
    for _ in range(count):
        if pos + 8 > end:
            raise ValueError("Truncated Mach-O load command")
        cmd, size = struct.unpack_from("<II", data, pos)
        if size < 8 or size % 8 or pos + size > end:
            raise ValueError("Invalid Mach-O load command size")
        if cmd == 0x32:  # LC_BUILD_VERSION
            if size < 24:
                raise ValueError("Truncated platform declaration")
            platform = struct.unpack_from("<I", data, pos + 8)[0]
        if cmd == 0x80000028:  # LC_MAIN
            if size < 24:
                raise ValueError("Truncated executable entry point")
            entry = struct.unpack_from("<Q", data, pos + 8)[0]
        if cmd == 0xC:  # LC_LOAD_DYLIB
            if size < 24:
                raise ValueError("Truncated dylib load command")
            offset = struct.unpack_from("<I", data, pos + 8)[0]
            if not 24 <= offset < size or b'\0' not in data[pos + offset:pos + size]:
                raise ValueError("Invalid dylib dependency name")
            dependencies.append(data[pos + offset:pos + size].split(b'\0')[0].decode('utf-8'))
        if cmd == 0x19:  # LC_SEGMENT_64
            if size < 72:
                raise ValueError("Truncated segment")
            file_offset, file_size = struct.unpack_from("<QQ", data, pos + 40)
            protection, sections = struct.unpack_from("<II", data, pos + 60)
            if file_offset + file_size > len(data) or 72 + sections * 80 > size:
                raise ValueError("Segment or section exceeds binary bounds")
            if protection & 4:
                for index in range(sections):
                    section = pos + 72 + index * 80
                    section_size = struct.unpack_from("<Q", data, section + 40)[0]
                    section_offset = struct.unpack_from("<I", data, section + 48)[0]
                    flags = struct.unpack_from("<I", data, section + 64)[0]
                    if flags & 0x80000400 and section_size:
                        if section_offset < end or section_offset + section_size > file_offset + file_size:
                            raise ValueError("Executable section exceeds segment bounds")
                        text_ranges.append((section_offset, section_offset + section_size))
        pos += size
    if pos != end or platform != 2:
        raise ValueError("Executable is not an iPhoneOS device build (platform 2)")
    if not text_ranges:
        raise ValueError("Image contains no executable section")
    if not dylib and (entry is None or not any(start <= entry < finish for start, finish in text_ranges)):
        raise ValueError("Entry point is not inside executable code")
    return dependencies


def windows_dll(data, machines=(0x8664,)):
    if len(data) < 512 or data[:2] != b"MZ":
        raise ValueError("Expected a real Windows PE DLL")
    pe = struct.unpack_from("<I", data, 60)[0]
    if pe < 64 or pe + 24 > len(data) or data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("Invalid PE signature or offset")
    machine, sections = struct.unpack_from("<HH", data, pe + 4)
    optional_size, flags = struct.unpack_from("<HH", data, pe + 20)
    opt = pe + 24
    if machine not in machines or not flags & 0x2000:
        raise ValueError("Wrong DLL architecture or missing DLL characteristic")
    if not 1 <= sections <= 96 or optional_size < 112 or opt + optional_size > len(data):
        raise ValueError("Invalid PE optional header or section count")
    if struct.unpack_from("<H", data, opt)[0] != 0x20B:
        raise ValueError("Expected a 64-bit PE32+ DLL")
    table = opt + optional_size
    if table + sections * 40 > len(data):
        raise ValueError("Truncated PE sections")
    executable = False
    for i in range(sections):
        section = table + i * 40
        raw_size, raw_offset = struct.unpack_from("<II", data, section + 16)
        characteristics = struct.unpack_from("<I", data, section + 36)[0]
        if raw_size and (raw_offset < table + sections * 40 or raw_offset + raw_size > len(data)):
            raise ValueError("PE section data exceeds DLL bounds")
        executable |= bool(raw_size and characteristics & 0x20000000)
    if not executable:
        raise ValueError("DLL contains no executable section")
