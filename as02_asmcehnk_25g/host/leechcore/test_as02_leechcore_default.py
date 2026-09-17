#!/usr/bin/env python3
"""Verify that the AS02 LeechCore DLL routes plain ``fpga`` to RawUDP.

The test uses a loopback-built DLL and observes the first UDP probe.  It does
not claim FPGA identity, BAR, or DMA success; those require a live board.
"""

import argparse
import ctypes
import json
import multiprocessing
import os
import socket
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


MAX_PATH = 260
LC_CONFIG_VERSION = 0xC0FD0002
EXPECTED_PROBE = bytes.fromhex(
    "6666555566665555666655556666555500000000000813770000000001000377"
)


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


def child_open(dll_path, device):
    dll = ctypes.WinDLL(str(dll_path))
    lc_create_ex = dll.LcCreateEx
    lc_create_ex.argtypes = [
        ctypes.POINTER(LC_CONFIG), ctypes.POINTER(ctypes.c_void_p)
    ]
    lc_create_ex.restype = ctypes.c_void_p
    config = LC_CONFIG()
    config.dwVersion = LC_CONFIG_VERSION
    config.szDevice = device.encode("ascii")
    error_info = ctypes.c_void_p()
    # The parent terminates this probe process after observing the datagram.
    lc_create_ex(ctypes.byref(config), ctypes.byref(error_info))


def observe(dll_path, device, port, timeout):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    sock.bind(("127.0.0.1", port))
    process = multiprocessing.Process(target=child_open,
                                      args=(str(dll_path), device), daemon=True)
    process.start()
    packet = None
    peer = None
    error = None
    try:
        packet, peer = sock.recvfrom(65535)
    except socket.timeout:
        error = "timeout waiting for UDP probe"
    finally:
        if process.is_alive():
            process.terminate()
        process.join(timeout=2.0)
        sock.close()
    return {
        "device": device,
        "observed": packet is not None,
        "peer": None if peer is None else f"{peer[0]}:{peer[1]}",
        "length": 0 if packet is None else len(packet),
        "payload_hex": None if packet is None else packet.hex(),
        "aligned_8": packet is not None and len(packet) % 8 == 0,
        "magic_77": packet is not None and packet[-1] == 0x77,
        "expected_vector": packet == EXPECTED_PROBE,
        "error": error,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dll", required=True, type=Path)
    parser.add_argument("--port", type=int, default=28474)
    parser.add_argument("--timeout", type=float, default=3.0)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if os.name != "nt":
        raise SystemExit("Windows DLL probe requires Windows")
    if not args.dll.is_file():
        raise SystemExit(f"DLL not found: {args.dll}")

    plain = observe(args.dll, "fpga", args.port, args.timeout)
    explicit = observe(args.dll, "fpga://ip=127.0.0.1", args.port, args.timeout)
    result = {
        "schema": "as02-leechcore-default-rawudp-v1",
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "dll": str(args.dll.resolve()),
        "dll_sha256": __import__("hashlib").sha256(args.dll.read_bytes()).hexdigest(),
        "plain_fpga": plain,
        "explicit_ip": explicit,
        "payloads_equal": plain["payload_hex"] == explicit["payload_hex"],
        "success": all((
            plain["observed"], plain["aligned_8"], plain["magic_77"],
            plain["expected_vector"], explicit["observed"],
            explicit["aligned_8"], explicit["magic_77"],
            explicit["expected_vector"],
            plain["payload_hex"] == explicit["payload_hex"],
        )),
    }
    rendered = json.dumps(result, indent=2, sort_keys=True)
    print(rendered)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
    return 0 if result["success"] else 1


if __name__ == "__main__":
    multiprocessing.freeze_support()
    sys.exit(main())
