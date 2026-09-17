#!/usr/bin/env python3
"""AS02 UDP correctness and stability test suite for a direct SFP1 link."""

import argparse
import json
import socket
import struct
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from as02_udp_smoke import build_loopback_word, decode_mux_payload


MAX_STANDARD_MTU_WORDS = 184


def percentile(values, fraction):
    if not values:
        return 0.0
    ordered = sorted(values)
    index = round((len(ordered) - 1) * fraction)
    return ordered[index]


def expected_values(iteration, word_count, seed):
    base = iteration * word_count
    return [((seed + base + index) * 0x9E3779B1) & 0xFFFFFFFF
            for index in range(word_count)]


def receive_loopback_words(sock, expected_count, deadline, target_ip, port):
    words = []
    packet_count = 0
    byte_count = 0
    unexpected_peers = []
    while len(words) < expected_count:
        remaining = deadline - time.perf_counter()
        if remaining <= 0:
            break
        sock.settimeout(remaining)
        try:
            payload, peer = sock.recvfrom(65535)
        except socket.timeout:
            break
        packet_count += 1
        byte_count += len(payload)
        if peer[0] != target_ip or peer[1] != port:
            unexpected_peers.append(f"{peer[0]}:{peer[1]}")
            continue
        for entry in decode_mux_payload(payload):
            if entry["tag"] == 2:
                words.append(int(entry["word"], 16))
    return words, packet_count, byte_count, unexpected_peers


def run_loopback_case(bind_ip, target_ip, port, timeout, iterations,
                      word_count, seed, name):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4 * 1024 * 1024)
    sock.bind((bind_ip, 0))
    latencies_ms = []
    total_commands = 0
    total_responses = 0
    total_tx_bytes = 0
    total_rx_bytes = 0
    total_rx_packets = 0
    missing = 0
    extra = 0
    corrupt = 0
    unexpected_peers = []
    failures = []
    suite_start = time.perf_counter()
    try:
        for iteration in range(iterations):
            expected = expected_values(iteration, word_count, seed)
            payload = b"".join(
                struct.pack(">Q", build_loopback_word(value))
                for value in expected
            )
            started = time.perf_counter()
            sock.sendto(payload, (target_ip, port))
            received, packet_count, rx_bytes, peers = receive_loopback_words(
                sock, len(expected), started + timeout, target_ip, port
            )
            latencies_ms.append((time.perf_counter() - started) * 1000)
            total_commands += len(expected)
            total_responses += len(received)
            total_tx_bytes += len(payload)
            total_rx_bytes += rx_bytes
            total_rx_packets += packet_count
            unexpected_peers.extend(peers)

            compare_count = min(len(expected), len(received))
            mismatch_count = sum(
                1 for index in range(compare_count)
                if expected[index] != received[index]
            )
            missing_count = max(0, len(expected) - len(received))
            extra_count = max(0, len(received) - len(expected))
            corrupt += mismatch_count
            missing += missing_count
            extra += extra_count
            if mismatch_count or missing_count or extra_count or peers:
                failures.append({
                    "iteration": iteration,
                    "expected_count": len(expected),
                    "received_count": len(received),
                    "missing": missing_count,
                    "extra": extra_count,
                    "corrupt": mismatch_count,
                    "unexpected_peers": peers,
                    "expected_head": [f"0x{value:08x}" for value in expected[:8]],
                    "received_head": [f"0x{value:08x}" for value in received[:8]],
                })
                if len(failures) >= 8:
                    break
    except OSError as error:
        failures.append({"socket_error": str(error)})
    finally:
        sock.close()

    elapsed = time.perf_counter() - suite_start
    success = (
        not failures and missing == 0 and extra == 0 and corrupt == 0 and
        not unexpected_peers and total_commands == total_responses
    )
    return {
        "name": name,
        "success": success,
        "iterations_requested": iterations,
        "iterations_completed": len(latencies_ms),
        "words_per_iteration": word_count,
        "commands_sent": total_commands,
        "responses_received": total_responses,
        "missing": missing,
        "extra": extra,
        "corrupt_or_reordered": corrupt,
        "unexpected_peers": sorted(set(unexpected_peers)),
        "tx_udp_payload_bytes": total_tx_bytes,
        "rx_udp_payload_bytes": total_rx_bytes,
        "rx_udp_packets": total_rx_packets,
        "elapsed_seconds": round(elapsed, 6),
        "functional_payload_mbps": round(
            ((total_tx_bytes + total_rx_bytes) * 8 / elapsed) / 1_000_000, 3
        ) if elapsed else 0.0,
        "latency_ms": {
            "p50": round(percentile(latencies_ms, 0.50), 3),
            "p95": round(percentile(latencies_ms, 0.95), 3),
            "max": round(max(latencies_ms), 3) if latencies_ms else 0.0,
        },
        "failures": failures,
    }


def expect_no_response(bind_ip, target_ip, port, payload, timeout, name):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((bind_ip, 0))
    started = time.perf_counter()
    observed = None
    error = None
    try:
        sock.settimeout(timeout)
        sock.sendto(payload, (target_ip, port))
        observed, peer = sock.recvfrom(65535)
        error = f"unexpected response from {peer[0]}:{peer[1]}"
    except socket.timeout:
        pass
    except OSError as socket_error:
        if getattr(socket_error, "winerror", None) != 10054:
            error = str(socket_error)
    finally:
        sock.close()
    return {
        "name": name,
        "success": observed is None and error is None,
        "elapsed_ms": round((time.perf_counter() - started) * 1000, 3),
        "unexpected_response_hex": None if observed is None else observed.hex(),
        "error": error,
    }


def parse_args():
    parser = argparse.ArgumentParser(
        description="Run AS02 SFP1 UDP burst, stability, and rejection tests."
    )
    parser.add_argument("--target", default="192.168.0.222")
    parser.add_argument("--port", type=int, default=28474)
    parser.add_argument("--bind", required=True)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--iterations", type=int, default=100)
    parser.add_argument("--batch-words", type=int, default=128)
    parser.add_argument("--negative-timeout", type=float, default=0.25)
    parser.add_argument("--seed", type=lambda value: int(value, 0),
                        default=0x4A6F7921)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not 1 <= args.port <= 65534:
        parser.error("--port must leave room for the wrong-port test")
    if not 1 <= args.iterations <= 100000:
        parser.error("--iterations must be between 1 and 100000")
    if not 1 <= args.batch_words <= MAX_STANDARD_MTU_WORDS:
        parser.error(
            f"--batch-words must be between 1 and {MAX_STANDARD_MTU_WORDS}"
        )
    if args.timeout <= 0 or args.negative_timeout <= 0:
        parser.error("timeouts must be positive")
    return args


def main():
    args = parse_args()
    max_burst = run_loopback_case(
        args.bind, args.target, args.port, args.timeout, 1,
        MAX_STANDARD_MTU_WORDS, args.seed ^ 0xA5020001,
        "maximum_standard_mtu_loopback"
    )
    sustained = run_loopback_case(
        args.bind, args.target, args.port, args.timeout, args.iterations,
        args.batch_words, args.seed, "sustained_loopback"
    )
    wrong_port = expect_no_response(
        args.bind, args.target, args.port + 1,
        struct.pack(">Q", build_loopback_word(0x6F3A0001)),
        args.negative_timeout, "wrong_udp_port_rejection"
    )
    malformed = expect_no_response(
        args.bind, args.target, args.port,
        struct.pack(">Q", build_loopback_word(0x6F3A0002)) + b"\x00",
        args.negative_timeout, "unaligned_payload_rejection"
    )
    cases = [max_burst, sustained, wrong_port, malformed]
    result = {
        "schema_version": 1,
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "target": f"{args.target}:{args.port}",
        "bind": args.bind,
        "line_rate_note": (
            "functional_payload_mbps is Python request/response throughput, "
            "not a 25G MAC line-rate measurement"
        ),
        "cases": cases,
        "success": all(case["success"] for case in cases),
    }
    rendered = json.dumps(result, indent=2, sort_keys=True)
    print(rendered)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
    if result["success"]:
        print("AS02_UDP_STRESS_TEST_PASS")
        return 0
    print("AS02_UDP_STRESS_TEST_FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())
