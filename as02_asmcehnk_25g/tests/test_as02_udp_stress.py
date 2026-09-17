import json
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

from as02_udp_smoke import decode_mux_payload


PROJECT_ROOT = Path(__file__).resolve().parents[1]
STRESS_TOOL = PROJECT_ROOT / "as02_udp_stress.py"


def encode_mux_words(words):
    payload = bytearray()
    context_bit_positions = (24, 28, 16, 20, 8, 12, 0)
    for offset in range(0, len(words), 7):
        chunk = words[offset:offset + 7]
        padded = chunk + [0xFFFFFFFF] * (7 - len(chunk))
        status = 0
        for index in range(len(chunk)):
            status |= 2 << context_bit_positions[index]
        payload.extend(struct.pack(">8I", status, *padded))
    return bytes(payload)


class MockAsmcehnkServer:
    def __init__(self, corrupt_first_response=False):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("127.0.0.1", 0))
        self.port = self.sock.getsockname()[1]
        self.stop_event = threading.Event()
        self.corrupt_first_response = corrupt_first_response
        self.thread = threading.Thread(target=self.run, daemon=True)

    def start(self):
        self.thread.start()

    def stop(self):
        self.stop_event.set()
        wake = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        wake.sendto(b"\x00", ("127.0.0.1", self.port))
        wake.close()
        self.thread.join(timeout=2)
        self.sock.close()

    def run(self):
        while not self.stop_event.is_set():
            payload, peer = self.sock.recvfrom(65535)
            if len(payload) == 0 or len(payload) % 8:
                continue
            responses = []
            for offset in range(0, len(payload), 8):
                command = struct.unpack_from(">Q", payload, offset)[0]
                if (command & 0xFF) != 0x77:
                    continue
                if ((command >> 8) & 0x3) == 2:
                    responses.append((command >> 32) & 0xFFFFFFFF)
            if responses:
                if self.corrupt_first_response:
                    responses[0] ^= 1
                    self.corrupt_first_response = False
                self.sock.sendto(encode_mux_words(responses), peer)


class As02UdpStressTests(unittest.TestCase):
    def test_leechcore_rawudp_wire_vectors(self):
        inactivity_enable = bytes([
            0x01, 0x00, 0x01, 0x00, 0x80, 0x02, 0x23, 0x77
        ])
        self.assertEqual(
            struct.pack(">Q", 0x0100010080022377),
            inactivity_enable,
        )

        words = [0x11223344, 0xA1B2C3D4]
        decoded = decode_mux_payload(encode_mux_words(words))
        self.assertEqual(
            [int(entry["word"], 16) for entry in decoded[:2]],
            words,
        )
        self.assertTrue(all(entry["tag"] == 2 for entry in decoded[:2]))

    def test_stress_suite_against_mock_endpoint(self):
        server = MockAsmcehnkServer()
        server.start()
        try:
            with tempfile.TemporaryDirectory() as temporary_directory:
                report = Path(temporary_directory) / "report.json"
                completed = subprocess.run(
                    [
                        sys.executable,
                        str(STRESS_TOOL),
                        "--bind", "127.0.0.1",
                        "--target", "127.0.0.1",
                        "--port", str(server.port),
                        "--iterations", "4",
                        "--batch-words", "32",
                        "--timeout", "1",
                        "--negative-timeout", "0.05",
                        "--output", str(report),
                    ],
                    cwd=PROJECT_ROOT,
                    capture_output=True,
                    text=True,
                    timeout=15,
                    check=False,
                )
                self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
                result = json.loads(report.read_text(encoding="utf-8"))
                self.assertTrue(result["success"])
                self.assertEqual(len(result["cases"]), 4)
                self.assertTrue(all(case["success"] for case in result["cases"]))
                self.assertIn("AS02_UDP_STRESS_TEST_PASS", completed.stdout)
        finally:
            server.stop()

    def test_corrupt_response_fails_suite(self):
        server = MockAsmcehnkServer(corrupt_first_response=True)
        server.start()
        try:
            with tempfile.TemporaryDirectory() as temporary_directory:
                report = Path(temporary_directory) / "report.json"
                completed = subprocess.run(
                    [
                        sys.executable,
                        str(STRESS_TOOL),
                        "--bind", "127.0.0.1",
                        "--target", "127.0.0.1",
                        "--port", str(server.port),
                        "--iterations", "1",
                        "--batch-words", "8",
                        "--timeout", "0.2",
                        "--negative-timeout", "0.02",
                        "--output", str(report),
                    ],
                    cwd=PROJECT_ROOT,
                    capture_output=True,
                    text=True,
                    timeout=15,
                    check=False,
                )
                self.assertNotEqual(completed.returncode, 0)
                result = json.loads(report.read_text(encoding="utf-8"))
                self.assertFalse(result["success"])
                self.assertGreater(
                    result["cases"][0]["corrupt_or_reordered"], 0
                )
                self.assertIn("AS02_UDP_STRESS_TEST_FAIL", completed.stdout)
        finally:
            server.stop()


if __name__ == "__main__":
    unittest.main()
