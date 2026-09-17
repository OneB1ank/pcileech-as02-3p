#!/usr/bin/env python3
"""Exercise the AS02 LeechCore adapter against a deterministic RawUDP peer.

The peer models FPGA v4 identity, PCIe configuration/DRP reads, BAR0 sizing,
and a small raw-TLP memory target.  This proves the host API contract through
real ``LcCreateEx``/``LcReadScatterEx``/``LcWrite`` calls without claiming a
live PCIe root-complex, CQ/CC, RQ/RC, SFP1, or board-DMA result.
"""

import argparse
import ctypes
import json
import os
import socket
import struct
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


MAX_PATH = 260
LC_CONFIG_VERSION = 0xC0FD0002
LC_OPT_FPGA_DEVICE_ID = 0x0300008000000000
LC_OPT_FPGA_FPGA_ID = 0x0300008100000000
LC_OPT_FPGA_VERSION_MAJOR = 0x0300008200000000
LC_OPT_FPGA_VERSION_MINOR = 0x0300008300000000
LC_CMD_FPGA_PCIECFGSPACE = 0x0000010300000000
LC_CMD_FPGA_CFGREGDRP = 0x0000010600000000
LC_CMD_FPGA_BAR_INFO = 0x0000012400000000
MEM_SCATTER_VERSION = 0xC0FE0002
LC_READ_PAGE_RESULT_SUCCESS = 0x01

TEST_BDF = 0x0300
TEST_VENDOR_ID = 0x10EE
TEST_DEVICE_ID = 0x0666
TEST_REVISION_ID = 0x02
TEST_CLASS_CODE = 0x0C0340
TEST_BAR0 = 0x80000000
TEST_READ32_ADDRESS = 0x00102000
TEST_READ64_ADDRESS = 0x0000000100102000
TEST_WRITE32_ADDRESS = 0x00103000
TEST_WRITE64_ADDRESS = 0x0000000100103000
TEST_TRANSFER_SIZE = 16


class LC_CONFIG(ctypes.Structure):
    _fields_ = [
        ("dwVersion", ctypes.c_uint32),
        ("dwPrintfVerbosity", ctypes.c_uint32),
        ("szDevice", ctypes.c_char * MAX_PATH),
        ("szRemote", ctypes.c_char * MAX_PATH),
        ("pfn_printf_opt", ctypes.c_void_p),
        ("paMax", ctypes.c_uint64),
        ("fVolatile", ctypes.c_int32),
        ("fWritable", ctypes.c_int32),
        ("fRemote", ctypes.c_int32),
        ("fRemoteDisableCompress", ctypes.c_int32),
        ("szDeviceName", ctypes.c_char * MAX_PATH),
    ]


class LC_BAR(ctypes.Structure):
    _fields_ = [
        ("fValid", ctypes.c_int32),
        ("fIO", ctypes.c_int32),
        ("f64Bit", ctypes.c_int32),
        ("fPrefetchable", ctypes.c_int32),
        ("_Filler", ctypes.c_uint32 * 3),
        ("iBar", ctypes.c_uint32),
        ("pa", ctypes.c_uint64),
        ("cb", ctypes.c_uint64),
    ]


class MEM_SCATTER(ctypes.Structure):
    _fields_ = [
        ("version", ctypes.c_uint32),
        ("f", ctypes.c_int32),
        ("qwA", ctypes.c_uint64),
        ("pb", ctypes.POINTER(ctypes.c_ubyte)),
        ("cb", ctypes.c_uint32),
        ("iStack", ctypes.c_uint32),
        ("vStack", ctypes.c_uint64 * 12),
    ]


def bswap16(value):
    return ((value & 0xFF) << 8) | ((value >> 8) & 0xFF)


def frame(source, words):
    status = 0xE0000000 | sum((source & 0xF) << (4 * i) for i in range(7))
    return struct.pack("<8I", status, *(list(words) + [0] * (7 - len(words))))


def cfg_word(address, first, second=0):
    return ((second & 0xFF) << 24) | ((first & 0xFF) << 16) | bswap16(address)


def cfg_reply(records, source):
    words = [cfg_word(address, first, second) for address, first, second in records]
    return b"".join(frame(source, words[i:i + 7]) for i in range(0, len(words), 7))


def pcie_reply(addresses):
    words = []
    for index in addresses:
        if index == 0:
            value = (TEST_DEVICE_ID << 16) | TEST_VENDOR_ID
        elif index == 2:
            value = (TEST_CLASS_CODE << 8) | TEST_REVISION_ID
        elif index == 4:
            value = TEST_BAR0
        elif index == 11:
            value = (0x0007 << 16) | TEST_VENDOR_ID
        else:
            value = 0
        words.extend((
            0x08002A00 | ((index & 0x3FF) << 16),
            (((value >> 8) & 0xFF) << 24) | ((value & 0xFF) << 16) | 0x2C00,
            (((value >> 24) & 0xFF) << 24) | (((value >> 16) & 0xFF) << 16) | 0x2E00,
        ))
    return b"".join(frame(1, words[i:i + 7]) for i in range(0, len(words), 7))


def drp_reply(addresses):
    words = []
    for index in addresses:
        lo, hi = (0x00, 0xF0) if index == 7 else ((0xFF, 0xFF) if index == 8 else (0, 0))
        words.extend((
            0x00001C80 | ((index & 0xFF) << 16),
            (hi << 24) | (lo << 16) | 0x2000,
        ))
    return b"".join(frame(3, words[i:i + 7]) for i in range(0, len(words), 7))


def memory_pattern(address, size):
    return bytes((((address + i) >> (i & 3)) ^ 0xA5 ^ i) & 0xFF
                 for i in range(size))


def tlp_reply(tlp):
    dwords = [tlp[i:i + 4] for i in range(0, len(tlp), 4)]
    blocks = []
    for base in range(0, len(dwords), 7):
        chunk = dwords[base:base + 7]
        status = 0xE0000000
        for slot in range(7):
            if slot >= len(chunk):
                nibble = 0x1
            else:
                index = base + slot
                nibble = ((0x8 if index == 0 else 0) |
                          (0x4 if index == len(dwords) - 1 else 0))
            status |= nibble << (slot * 4)
        blocks.append(struct.pack("<I", status) + b"".join(chunk) +
                      b"\x00" * (4 * (7 - len(chunk))))
    return b"".join(blocks)


def completion_for_request(tlp, address, size):
    requester_id = tlp[4:6]
    tag = tlp[6]
    payload = memory_pattern(address, size)
    length_dw = size // 4
    header = bytes((0x4A, 0x00, (length_dw >> 8) & 0x03,
                    length_dw & 0xFF))
    header += TEST_BDF.to_bytes(2, "big")
    header += (size & 0x0FFF).to_bytes(2, "big")
    header += requester_id + bytes((tag, address & 0x7F))
    return header + payload


def handle_raw_tlp(sock, peer, tlp, stats, state):
    if len(tlp) < 12:
        stats["tlp_malformed"] += 1
        return
    type_fmt = tlp[0]
    length_dw = ((tlp[2] & 0x03) << 8) | tlp[3]
    length_dw = 1024 if length_dw == 0 else length_dw
    if type_fmt in (0x00, 0x20):
        header_size = 12 if type_fmt == 0x00 else 16
        if len(tlp) != header_size:
            stats["tlp_malformed"] += 1
            return
        if type_fmt == 0x00:
            address = int.from_bytes(tlp[8:12], "big") & ~0x3
        else:
            address = int.from_bytes(tlp[8:16], "big") & ~0x3
        size = length_dw * 4
        response = completion_for_request(tlp, address, size)
        sock.sendto(tlp_reply(response), peer)
        sock.sendto(struct.pack("<II", 0xEFFFFFF3, 0xDECEFFFF) +
                    b"\x00" * 24, peer)
        state["mrd"].append({"type": type_fmt, "address": address,
                             "size": size, "tag": tlp[6]})
        stats["mrd"] += 1
        stats["cpld"] += 1
        return
    if type_fmt in (0x40, 0x60):
        header_size = 12 if type_fmt == 0x40 else 16
        size = length_dw * 4
        if len(tlp) != header_size + size:
            stats["tlp_malformed"] += 1
            return
        if type_fmt == 0x40:
            address = int.from_bytes(tlp[8:12], "big") & ~0x3
        else:
            address = int.from_bytes(tlp[8:16], "big") & ~0x3
        state["mwr"].append({"type": type_fmt, "address": address,
                             "size": size,
                             "payload_hex": tlp[header_size:].hex()})
        stats["mwr"] += 1
        return
    stats["tlp_other"] += 1


def serve_packet(sock, packet, peer, stats, state):
    if len(packet) % 8 or not packet:
        stats["malformed"] += 1
        return
    records = []
    for offset in range(0, len(packet), 8):
        record = packet[offset:offset + 8]
        if record == b"\x66\x66\x55\x55\x66\x66\x55\x55":
            stats["sync_fillers"] += 1
        else:
            records.append(record)
    if not records:
        stats["probes"] += 1
        return
    if any(record[7] != 0x77 for record in records):
        stats["bad_magic"] += 1
        return
    pcie = [record[0] | ((record[1] & 0x03) << 8)
            for record in records if record[6] == 0x21 and record[4:6] == b"\x80\x14"]
    drp = [record[0] for record in records
           if record[6] == 0x23 and record[4:6] == b"\x80\x1c"]
    if pcie:
        sock.sendto(pcie_reply(pcie), peer)
        stats["pcie_batches"] += 1
        return
    if drp:
        sock.sendto(drp_reply(drp), peer)
        stats["drp_batches"] += 1
        return
    reads = []
    for record in records:
        if record[6] & 0x30 != 0x10:
            continue
        source = record[6] & 0x03
        address = ((record[4] & 0x3F) << 8) | record[5]
        if source == 3 and address == 0x0008:
            reads.append((address, 4, 13))
        elif source == 3 and address == 0x000A:
            reads.append((address, 5, 0))
        elif source == 1 and address == 0x0008:
            reads.append((address, (TEST_BDF >> 8) & 0xFF,
                          TEST_BDF & 0xFF))
        else:
            reads.append((address, 0, 0))
    if reads:
        source = records[0][6] & 0x03
        sock.sendto(cfg_reply(reads, source), peer)
        stats["cfg_batches"] += 1
        return

    saw_raw_tlp = False
    for record in records:
        marker = record[6] & 0x0F
        if marker & 0x03 or marker not in (0x00, 0x04, 0x08, 0x0C):
            continue
        if marker & 0x08:
            state["tlp_bytes"].clear()
        state["tlp_bytes"].extend(record[:4])
        saw_raw_tlp = True
        if marker & 0x04:
            handle_raw_tlp(sock, peer, bytes(state["tlp_bytes"]), stats, state)
            state["tlp_bytes"].clear()
    if not saw_raw_tlp:
        stats["probes"] += 1


def child_main(dll_path):
    dll = ctypes.WinDLL(str(dll_path))
    dll.LcCreateEx.argtypes = [ctypes.POINTER(LC_CONFIG), ctypes.POINTER(ctypes.c_void_p)]
    dll.LcCreateEx.restype = ctypes.c_void_p
    dll.LcClose.argtypes = [ctypes.c_void_p]
    dll.LcGetOption.argtypes = [ctypes.c_void_p, ctypes.c_uint64, ctypes.POINTER(ctypes.c_uint64)]
    dll.LcGetOption.restype = ctypes.c_int
    dll.LcCommand.argtypes = [ctypes.c_void_p, ctypes.c_uint64, ctypes.c_uint32,
                              ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p),
                              ctypes.POINTER(ctypes.c_uint32)]
    dll.LcCommand.restype = ctypes.c_int
    dll.LcMemFree.argtypes = [ctypes.c_void_p]
    dll.LcReadScatterEx.argtypes = [
        ctypes.c_void_p, ctypes.c_uint32,
        ctypes.POINTER(ctypes.POINTER(MEM_SCATTER)),
        ctypes.POINTER(ctypes.c_uint32),
    ]
    dll.LcReadScatterEx.restype = ctypes.c_int
    dll.LcWrite.argtypes = [ctypes.c_void_p, ctypes.c_uint64,
                            ctypes.c_uint32,
                            ctypes.POINTER(ctypes.c_ubyte)]
    dll.LcWrite.restype = ctypes.c_int

    config = LC_CONFIG()
    config.dwVersion = LC_CONFIG_VERSION
    config.szDevice = b"fpga"
    config.paMax = 0x0000000200000000
    error_info = ctypes.c_void_p()
    handle = dll.LcCreateEx(ctypes.byref(config), ctypes.byref(error_info))
    result = {
        "create_ok": bool(handle),
        "device_name": bytes(config.szDeviceName).split(b"\0", 1)[0].decode("ascii", "replace"),
    }
    if error_info.value:
        dll.LcMemFree(error_info)
    if not handle:
        print(json.dumps(result, sort_keys=True), flush=True)
        return 1

    for name, option in (
        ("device_id", LC_OPT_FPGA_DEVICE_ID),
        ("fpga_id", LC_OPT_FPGA_FPGA_ID),
        ("version_major", LC_OPT_FPGA_VERSION_MAJOR),
        ("version_minor", LC_OPT_FPGA_VERSION_MINOR),
    ):
        value = ctypes.c_uint64()
        result[name + "_ok"] = bool(dll.LcGetOption(handle, option, ctypes.byref(value)))
        result[name] = int(value.value)

    def command(command_id):
        output = ctypes.c_void_p()
        size = ctypes.c_uint32()
        ok = bool(dll.LcCommand(handle, command_id, 0, None,
                                ctypes.byref(output), ctypes.byref(size)))
        data = ctypes.string_at(output, size.value) if output.value and size.value else b""
        if output.value:
            dll.LcMemFree(output)
        return ok, data

    ok, data = command(LC_CMD_FPGA_PCIECFGSPACE)
    result["pcie_cfg_ok"] = ok
    result["pcie_cfg_size"] = len(data)
    result["vid_did"] = struct.unpack_from("<I", data, 0)[0] if len(data) >= 4 else None
    result["class_revision"] = struct.unpack_from("<I", data, 8)[0] if len(data) >= 12 else None
    result["bar0_cfg"] = struct.unpack_from("<I", data, 0x10)[0] if len(data) >= 0x14 else None
    result["subsystem"] = struct.unpack_from("<I", data, 0x2C)[0] if len(data) >= 0x30 else None

    ok, data = command(LC_CMD_FPGA_BAR_INFO)
    result["bar_info_ok"] = ok
    result["bar_info_size"] = len(data)
    if len(data) >= ctypes.sizeof(LC_BAR):
        bar = LC_BAR.from_buffer_copy(data[:ctypes.sizeof(LC_BAR)])
        result["bar0"] = {"valid": bool(bar.fValid), "io": bool(bar.fIO),
                           "64bit": bool(bar.f64Bit), "prefetchable": bool(bar.fPrefetchable),
                           "address": int(bar.pa), "size": int(bar.cb)}

    ok, data = command(LC_CMD_FPGA_CFGREGDRP)
    result["drp_ok"] = ok
    result["drp_size"] = len(data)
    result["drp_raw_14_18"] = data[14:18].hex() if len(data) >= 18 else None
    if len(data) >= 18:
        normalized = data[15:16] + data[14:15] + data[17:18] + data[16:17]
        result["drp_bar0_mask"] = struct.unpack("<I", normalized)[0]

    def read_scatter(address):
        buffer = (ctypes.c_ubyte * TEST_TRANSFER_SIZE)()
        memory = MEM_SCATTER()
        memory.version = MEM_SCATTER_VERSION
        memory.qwA = address
        memory.pb = ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte))
        memory.cb = TEST_TRANSFER_SIZE
        memory_pointer = ctypes.pointer(memory)
        memories = (ctypes.POINTER(MEM_SCATTER) * 1)(memory_pointer)
        page_result = ctypes.c_uint32()
        ok_read = bool(dll.LcReadScatterEx(handle, 1, memories,
                                           ctypes.byref(page_result)))
        return {"ok": ok_read, "page_result": page_result.value,
                "memory_success": bool(memory.f),
                "data_hex": bytes(buffer).hex()}

    result["read32"] = read_scatter(TEST_READ32_ADDRESS)
    result["read64"] = read_scatter(TEST_READ64_ADDRESS)

    write32 = memory_pattern(TEST_WRITE32_ADDRESS, TEST_TRANSFER_SIZE)
    write64 = memory_pattern(TEST_WRITE64_ADDRESS, TEST_TRANSFER_SIZE)
    write32_buffer = (ctypes.c_ubyte * len(write32)).from_buffer_copy(write32)
    write64_buffer = (ctypes.c_ubyte * len(write64)).from_buffer_copy(write64)
    result["write32_ok"] = bool(dll.LcWrite(handle, TEST_WRITE32_ADDRESS,
                                            len(write32), write32_buffer))
    result["write64_ok"] = bool(dll.LcWrite(handle, TEST_WRITE64_ADDRESS,
                                            len(write64), write64_buffer))
    result["write32_data_hex"] = write32.hex()
    result["write64_data_hex"] = write64.hex()

    dll.LcClose(handle)
    print(json.dumps(result, sort_keys=True), flush=True)
    child_success = all((
        result["pcie_cfg_ok"], result["bar_info_ok"], result["drp_ok"],
        result["read32"]["ok"], result["read32"]["memory_success"],
        result["read64"]["ok"], result["read64"]["memory_success"],
        result["write32_ok"], result["write64_ok"],
    ))
    return 0 if child_success else 1


def run_test(dll_path, port, timeout):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", port))
    sock.settimeout(0.05)
    process = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--child", str(dll_path)],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    stats = {"probes": 0, "cfg_batches": 0, "pcie_batches": 0,
             "drp_batches": 0, "malformed": 0, "bad_magic": 0,
             "tlp_malformed": 0, "tlp_other": 0, "mrd": 0, "mwr": 0,
             "cpld": 0, "sync_fillers": 0}
    state = {"tlp_bytes": bytearray(), "mrd": [], "mwr": []}
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline and process.poll() is None:
        try:
            packet, peer = sock.recvfrom(65535)
        except socket.timeout:
            continue
        serve_packet(sock, packet, peer, stats, state)
    if process.poll() is None:
        process.kill()
    stdout, _ = process.communicate(timeout=5)
    sock.close()
    child = None
    for line in reversed(stdout.splitlines()):
        if line.startswith("{"):
            try:
                child = json.loads(line)
                break
            except json.JSONDecodeError:
                pass
    checks = {
        "create": bool(child and child.get("create_ok")),
        "identity": bool(child and child.get("device_id_ok") and child.get("device_id") == TEST_BDF
                        and child.get("fpga_id_ok") and child.get("fpga_id") == 5
                        and child.get("version_major_ok") and child.get("version_major") == 4
                        and child.get("version_minor_ok") and child.get("version_minor") == 13),
        "pcie_cfg": bool(child and child.get("pcie_cfg_ok") and child.get("pcie_cfg_size") == 0x1000
                     and child.get("vid_did") == ((TEST_DEVICE_ID << 16) | TEST_VENDOR_ID)
                     and child.get("class_revision") == ((TEST_CLASS_CODE << 8) | TEST_REVISION_ID)
                     and child.get("bar0_cfg") == TEST_BAR0
                     and child.get("subsystem") == ((0x0007 << 16) | TEST_VENDOR_ID)),
        "bar_info": bool(child and child.get("bar_info_ok") and child.get("bar0", {}).get("valid")
                         and not child.get("bar0", {}).get("io") and not child.get("bar0", {}).get("64bit")
                         and not child.get("bar0", {}).get("prefetchable")
                         and child.get("bar0", {}).get("address") == 0x80000000
                         and child.get("bar0", {}).get("size") == 0x1000),
        "drp": bool(child and child.get("drp_ok") and child.get("drp_size") == 0x100
                    and child.get("drp_raw_14_18") == "f000ffff"
                    and child.get("drp_bar0_mask") == 0xFFFFF000),
        "read32": bool(child and child.get("read32", {}).get("ok")
                       and child.get("read32", {}).get("page_result") == LC_READ_PAGE_RESULT_SUCCESS
                       and child.get("read32", {}).get("memory_success")
                       and child.get("read32", {}).get("data_hex") ==
                       memory_pattern(TEST_READ32_ADDRESS, TEST_TRANSFER_SIZE).hex()),
        "read64": bool(child and child.get("read64", {}).get("ok")
                       and child.get("read64", {}).get("page_result") == LC_READ_PAGE_RESULT_SUCCESS
                       and child.get("read64", {}).get("memory_success")
                       and child.get("read64", {}).get("data_hex") ==
                       memory_pattern(TEST_READ64_ADDRESS, TEST_TRANSFER_SIZE).hex()),
        "write32": bool(child and child.get("write32_ok") and
                        any(item.get("type") == 0x40 and
                            item.get("address") == TEST_WRITE32_ADDRESS and
                            item.get("payload_hex") == child.get("write32_data_hex")
                            for item in state["mwr"])),
        "write64": bool(child and child.get("write64_ok") and
                        any(item.get("type") == 0x60 and
                            item.get("address") == TEST_WRITE64_ADDRESS and
                            item.get("payload_hex") == child.get("write64_data_hex")
                            for item in state["mwr"])),
        "raw_tlp": bool(stats["mrd"] >= 2 and stats["mwr"] >= 2 and
                        stats["cpld"] >= 2 and not stats["tlp_malformed"]),
        "transport_activity": bool(stats["cfg_batches"] and stats["pcie_batches"] and stats["drp_batches"]),
    }
    result = {
        "schema": "as02-leechcore-api-mock-v1",
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "dll": str(Path(dll_path).resolve()),
        "child_exit_code": process.returncode,
        "child_output": child,
        "server": stats,
        "raw_tlp": {"mrd": state["mrd"], "mwr": state["mwr"]},
        "checks": checks,
        "success": all(checks.values()) and process.returncode == 0,
    }
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--child", type=Path)
    parser.add_argument("--dll", type=Path,
                        default=Path(__file__).with_name(".test_out") / "leechcore_as02_rawudp_x64.dll")
    parser.add_argument("--port", type=int, default=28474)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if os.name != "nt":
        raise SystemExit("Windows DLL API test requires Windows")
    if args.child:
        return child_main(args.child)
    if not args.dll.is_file():
        raise SystemExit("DLL not found: " + str(args.dll))
    result = run_test(args.dll, args.port, args.timeout)
    rendered = json.dumps(result, indent=2, sort_keys=True)
    print(rendered)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
    return 0 if result["success"] else 1


if __name__ == "__main__":
    sys.exit(main())
