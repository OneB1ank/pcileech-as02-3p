#!/usr/bin/env python3
"""Minimal dependency-free AS02 rawudp smoke stimulus and evidence logger."""

import argparse
import json
import socket
import struct
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


READ_ADDRESSES = (0x0000, 0x0004, 0x0006, 0x0008, 0x000A, 0x0024, 0x0026)


def build_read_word(address):
    return ((address & 0xFFFF) << 16) | (1 << 12) | (3 << 8) | 0x77


def build_loopback_word(value):
    return ((value & 0xFFFFFFFF) << 32) | (2 << 8) | 0x77


def swap16(value):
    return ((value & 0xFF) << 8) | ((value >> 8) & 0xFF)


def mux_contexts(status):
    return (
        (status >> 24) & 0xF,
        (status >> 28) & 0xF,
        (status >> 16) & 0xF,
        (status >> 20) & 0xF,
        (status >> 8) & 0xF,
        (status >> 12) & 0xF,
        status & 0xF,
    )


def decode_mux_payload(payload):
    decoded = []
    full_blocks = len(payload) // 32
    for block_index in range(full_blocks):
        block = payload[block_index * 32:(block_index + 1) * 32]
        wire_words = struct.unpack(">8I", block)
        data_words = wire_words[1:]
        contexts = mux_contexts(wire_words[0])
        for slot, (word, context) in enumerate(zip(data_words, contexts)):
            decoded.append({
                "block": block_index,
                "slot": slot,
                "word": f"0x{word:08x}",
                "context": context,
                "tag": context & 0x3,
                "stream_context": (context >> 2) & 0x3,
            })
    return decoded


def probe_checks(decoded, major, minor, device, custom):
    expected = {
        0x0000: 0xAB89,
        0x0004: 0x0028,
        0x0006: 0x0000,
        0x0008: ((minor & 0xFF) << 8) | (major & 0xFF),
        0x000A: device & 0xFF,
        0x0024: custom & 0xFFFF,
        0x0026: (custom >> 16) & 0xFFFF,
    }
    observed = {}
    for entry in decoded:
        if entry["tag"] != 3:
            continue
        word = int(entry["word"], 16)
        if word == 0xFFFFFFFF:
            continue
        address = (word >> 16) & 0xFFFF
        observed[address] = swap16(word & 0xFFFF)

    checks = []
    for address in READ_ADDRESSES:
        actual = observed.get(address)
        checks.append({
            "address": f"0x{address:04x}",
            "expected": f"0x{expected[address]:04x}",
            "actual": None if actual is None else f"0x{actual:04x}",
            "pass": actual == expected[address],
        })
    return checks


def loopback_checks(decoded, value):
    words = [int(entry["word"], 16) for entry in decoded if entry["tag"] == 2]
    return [{
        "expected": f"0x{value:08x}",
        "actual": None if not words else f"0x{words[0]:08x}",
        "pass": bool(words) and words[0] == value,
    }]


def parse_args():
    parser = argparse.ArgumentParser(
        description="Send a deterministic aligned rawudp probe to AS02 SFP1."
    )
    parser.add_argument("--target", default="192.168.0.222")
    parser.add_argument("--port", type=int, default=28474)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--bind-port", type=int, default=0)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--mode", choices=("probe", "loopback"), default="probe")
    parser.add_argument("--loopback-value", type=lambda value: int(value, 0),
                        default=0x11223344)
    parser.add_argument("--expect-major", type=int, default=4)
    parser.add_argument("--expect-minor", type=int, default=13)
    parser.add_argument("--expect-device", type=int, default=5)
    parser.add_argument("--expect-custom", type=lambda value: int(value, 0),
                        default=0xFFFFFFFF)
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main():
    args = parse_args()
    if args.mode == "probe":
        tx_words = [build_read_word(address) for address in READ_ADDRESSES]
    else:
        tx_words = [build_loopback_word(args.loopback_value)]
    tx_payload = b"".join(struct.pack(">Q", word) for word in tx_words)

    result = {
        "schema_version": 1,
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "mode": args.mode,
        "target": f"{args.target}:{args.port}",
        "bind": f"{args.bind}:{args.bind_port}",
        "tx_words": [f"0x{word:016x}" for word in tx_words],
        "tx_payload_hex": tx_payload.hex(),
    }

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(args.timeout)
    sock.bind((args.bind, args.bind_port))
    start = time.perf_counter()
    try:
        sock.sendto(tx_payload, (args.target, args.port))
        rx_payload, peer = sock.recvfrom(65535)
        result["peer"] = f"{peer[0]}:{peer[1]}"
        result["rx_payload_hex"] = rx_payload.hex()
        result["rx_length"] = len(rx_payload)
        result["elapsed_ms"] = round((time.perf_counter() - start) * 1000, 3)
        result["aligned_32_bytes"] = (len(rx_payload) % 32) == 0
        result["decoded"] = decode_mux_payload(rx_payload)
        if args.mode == "probe":
            result["checks"] = probe_checks(
                result["decoded"], args.expect_major, args.expect_minor,
                args.expect_device, args.expect_custom
            )
        else:
            result["checks"] = loopback_checks(
                result["decoded"], args.loopback_value
            )
        result["success"] = result["aligned_32_bytes"] and all(
            check["pass"] for check in result["checks"]
        )
    except socket.timeout:
        result["elapsed_ms"] = round((time.perf_counter() - start) * 1000, 3)
        result["error"] = "timeout waiting for AS02 UDP response"
        result["success"] = False
    except OSError as error:
        result["elapsed_ms"] = round((time.perf_counter() - start) * 1000, 3)
        result["error"] = str(error)
        result["success"] = False
    finally:
        sock.close()

    rendered = json.dumps(result, indent=2, sort_keys=True)
    print(rendered)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
    return 0 if result["success"] else 1


if __name__ == "__main__":
    sys.exit(main())
