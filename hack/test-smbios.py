#!/usr/bin/env python3
# SPDX-FileCopyrightText: © 2026 VEXXHOST, Inc.
# SPDX-License-Identifier: Apache-2.0

"""Inspect QEMU's SMBIOS tables and SeaBIOS discovery without a guest image.

Usage: python3 hack/test-smbios.py --qemu /path/to/qemu-system-x86_64
Use --bios /path/to/bios.bin when testing an uninstalled QEMU build.
"""

import argparse
import contextlib
import json
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import time
import unittest
import uuid


SYSTEM_UUID = uuid.UUID("00112233-4455-6677-8899-aabbccddeeff")
MACHINES = (
    "pc-i440fx-8.1",
    "pc-i440fx-8.2",
    "pc-i440fx-noble",
    "pc-i440fx-noble-v2",
    "pc-q35-8.1",
    "pc-q35-8.2",
    "pc-q35-noble",
    "pc-q35-noble-v2",
)


class Qemu:
    def __init__(self, directory, machine, extra=()):
        self.directory = Path(directory)
        self.qtest_path = self.directory / "qtest.sock"
        self.qmp_path = self.directory / "qmp.sock"
        self.command = [
            OPTIONS.qemu,
            "-machine",
            machine,
            "-accel",
            "tcg",
            "-nodefaults",
            "-display",
            "none",
            "-monitor",
            "none",
            "-serial",
            "none",
            "-S",
            "-m",
            "128",
            "-qtest",
            f"unix:{self.qtest_path},server=on,wait=off",
            "-qmp",
            f"unix:{self.qmp_path},server=on,wait=off",
            "-uuid",
            str(SYSTEM_UUID),
            "-smbios",
            "type=1,manufacturer=VEXXHOST,product=SMBIOS-test," "serial=test-serial",
        ]
        if OPTIONS.bios:
            self.command += ["-bios", OPTIONS.bios]
        self.command += extra
        self.resources = contextlib.ExitStack()

    def connect(self, path):
        connection = self.resources.enter_context(socket.socket(socket.AF_UNIX))
        connection.settimeout(10)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise AssertionError(self.log.read_text())
            try:
                connection.connect(str(path))
                return self.resources.enter_context(connection.makefile("rwb"))
            except (FileNotFoundError, ConnectionRefusedError):
                time.sleep(0.01)
        raise AssertionError(f"Timed out connecting to {path}: {self.log.read_text()}")

    def __enter__(self):
        self.log = self.directory / "qemu.log"
        output = self.resources.enter_context(self.log.open("wb"))
        self.process = subprocess.Popen(
            self.command,
            stdout=output,
            stderr=output,
        )
        try:
            self.qtest = self.connect(self.qtest_path)
            self.qmp = self.connect(self.qmp_path)
            if "QMP" not in json.loads(self.qmp.readline()):
                raise AssertionError("Missing QMP greeting")
            self.qmp_command("qmp_capabilities")
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *args):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.resources.close()

    def qmp_command(self, command):
        self.qmp.write(json.dumps({"execute": command}).encode() + b"\n")
        self.qmp.flush()
        while True:
            reply = json.loads(self.qmp.readline())
            if "return" in reply:
                return reply["return"]
            if "error" in reply:
                raise AssertionError(reply)

    def request(self, command):
        self.qtest.write(command.encode() + b"\n")
        self.qtest.flush()
        while True:
            reply = self.qtest.readline().decode().strip()
            if reply.startswith("IRQ "):
                continue
            if not reply.startswith("OK"):
                raise AssertionError(f"{command}: {reply}: {self.log.read_text()}")
            return reply.split()[1:]

    def read_memory(self, address, size):
        return bytes.fromhex(self.request(f"read {address:#x} {size:#x}")[0][2:])

    def fw_cfg(self, selector, size):
        # Read through fw_cfg DMA to avoid one socket round trip per byte.
        descriptor_address, buffer_address = 0x1000, 0x10000
        control = (selector << 16) | 0x08 | 0x02  # SELECT | READ
        descriptor = struct.pack(">IIQ", control, size, buffer_address)
        self.request(f"write {descriptor_address:#x} 0x10 0x{descriptor.hex()}")
        self.request("outl 0x514 0")
        low_address = int.from_bytes(descriptor_address.to_bytes(4, "big"), "little")
        self.request(f"outl 0x518 {low_address:#x}")
        if self.read_memory(descriptor_address, 4) != bytes(4):
            raise AssertionError("fw_cfg DMA did not complete")
        return self.read_memory(buffer_address, size)

    def smbios(self):
        count = int.from_bytes(self.fw_cfg(0x19, 4), "big")
        directory = self.fw_cfg(0x19, 4 + count * 64)
        files = {}
        for offset in range(4, len(directory), 64):
            size, selector, name = struct.unpack_from(">IH2x56s", directory, offset)
            name = name.rstrip(b"\0").decode()
            if name in ("etc/smbios/smbios-anchor", "etc/smbios/smbios-tables"):
                files[name] = self.fw_cfg(selector, size)
        return files["etc/smbios/smbios-anchor"], files["etc/smbios/smbios-tables"]


def records(tables):
    result = []
    offset = 0
    while offset < len(tables):
        if offset + 4 > len(tables) or tables[offset + 1] < 4:
            raise AssertionError("Malformed SMBIOS structure header")
        end = tables.find(b"\0\0", offset + tables[offset + 1])
        if end == -1:
            raise AssertionError("Missing SMBIOS structure terminator")
        result.append(tables[offset : end + 2])
        offset = end + 2
    return result


class SMBIOS(unittest.TestCase):
    def read_tables(self, machine, extra=()):
        with tempfile.TemporaryDirectory(prefix="smbios-test-") as directory:
            with Qemu(directory, machine, extra) as vm:
                return vm.smbios()

    def assert_startup_error(self, machine, extra, message):
        with tempfile.TemporaryDirectory(prefix="smbios-error-") as directory:
            vm = Qemu(directory, machine, extra)
            result = subprocess.run(
                vm.command,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=10,
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stderr)

    def assert_tables(self, anchor, tables, version):
        self.assertTrue(anchor.startswith(b"_SM_" if version == 2 else b"_SM3_"))
        parsed = records(tables)
        identity = [record for record in parsed if record[0] == 1]
        self.assertEqual(len(identity), 1)
        identity = identity[0]
        self.assertEqual(uuid.UUID(bytes_le=identity[8:24]), SYSTEM_UUID)
        strings = identity[identity[1] : -2].split(b"\0")
        for field, expected in (
            (4, b"VEXXHOST"),
            (5, b"SMBIOS-test"),
            (7, b"test-serial"),
        ):
            self.assertEqual(strings[identity[field] - 1], expected)
        self.assertEqual(sum(record[0] == 4 for record in parsed), 1)
        self.assertEqual(sum(record[0] == 127 for record in parsed), 1)
        if version == 2:
            self.assertEqual(struct.unpack_from("<H", anchor, 22)[0], len(tables))
            self.assertEqual(struct.unpack_from("<H", anchor, 28)[0], len(parsed))
        else:
            self.assertEqual(struct.unpack_from("<I", anchor, 12)[0], len(tables))

    def test_affected_machine_defaults(self):
        for machine in MACHINES:
            with self.subTest(machine=machine):
                self.assert_tables(*self.read_tables(machine), 2)

    def test_old_machine_defaults(self):
        for machine in (
            "pc-i440fx-8.0",
            "pc-q35-8.0",
            "pc-i440fx-mantic",
            "pc-q35-mantic",
        ):
            with self.subTest(machine=machine):
                self.assert_tables(*self.read_tables(machine), 2)

    def test_explicit_entry_points(self):
        for machine in ("pc-i440fx-noble", "pc-q35-noble"):
            for entry_point, version in (("auto", 2), ("32", 2), ("64", 3)):
                with self.subTest(machine=machine, entry_point=entry_point):
                    self.assert_tables(
                        *self.read_tables(
                            f"{machine},smbios-entry-point-type={entry_point}"
                        ),
                        version,
                    )

    def test_processor_count_fallback(self):
        # One populated vCPU keeps the test small; the socket topology requires v3.
        topology = ["-smp", "1,maxcpus=255,sockets=1,cores=255,threads=1"]
        for machine in ("pc-i440fx-noble", "pc-q35-noble"):
            with self.subTest(machine=machine):
                anchor, tables = self.read_tables(machine, topology)
                self.assert_tables(anchor, tables, 3)
                processor = next(record for record in records(tables) if record[0] == 4)
                self.assertEqual(struct.unpack_from("<H", processor, 42)[0], 255)
                self.assert_startup_error(
                    f"{machine},smbios-entry-point-type=32",
                    topology,
                    "core/thread count",
                )

    def test_large_table_fallback_preserves_user_blobs(self):
        _, normal_tables = self.read_tables(
            "pc-i440fx-noble,smbios-entry-point-type=64"
        )
        processor = next(record for record in records(normal_tables) if record[0] == 4)
        oem = struct.pack("<BBHB", 11, 5, 0xEE00, 1) + b"X" * 65536 + b"\0\0"
        with tempfile.TemporaryDirectory(prefix="smbios-blobs-") as directory:
            processor_file = Path(directory) / "processor.bin"
            processor_file.write_bytes(processor)
            oem_file = Path(directory) / "oem.bin"
            oem_file.write_bytes(oem)
            args = ["-smbios", f"file={processor_file}", "-smbios", f"file={oem_file}"]
            for machine in ("pc-i440fx-noble", "pc-q35-noble"):
                with self.subTest(machine=machine):
                    anchor, tables = self.read_tables(machine, args)
                    self.assert_tables(anchor, tables, 3)
                    self.assertEqual(
                        tables[: len(processor) + len(oem)], processor + oem
                    )
                    explicit = self.read_tables(
                        f"{machine},smbios-entry-point-type=64", args
                    )
                    self.assertEqual((anchor, tables), explicit)
                    self.assert_startup_error(
                        f"{machine},smbios-entry-point-type=32", args, "table length"
                    )

    def test_invalid_device_is_not_hidden_by_fallback(self):
        self.assert_startup_error(
            "pc-i440fx-noble",
            [
                "-smbios",
                "type=41,designation=test,kind=ethernet,pcidev=missing-device",
            ],
            "No PCI device",
        )

    def test_seabios_discovers_identity(self):
        for machine in ("pc-i440fx-noble", "pc-q35-noble"):
            with self.subTest(machine=machine):
                with tempfile.TemporaryDirectory(prefix="smbios-boot-") as directory:
                    with Qemu(directory, machine) as vm:
                        vm.qmp_command("cont")
                        deadline = time.monotonic() + 10
                        while time.monotonic() < deadline:
                            memory = vm.read_memory(0xF0000, 0x10000)
                            candidates = [
                                offset
                                for offset in range(0, len(memory) - 31, 16)
                                if memory[offset : offset + 4] == b"_SM_"
                            ]
                            if candidates:
                                break
                            time.sleep(0.05)
                        else:
                            self.fail(
                                "SeaBIOS did not publish a 32-bit SMBIOS entry point"
                            )
                        vm.qmp_command("stop")
                        anchor = vm.read_memory(0xF0000 + candidates[0], 31)
                        self.assertEqual(sum(anchor) % 256, 0)
                        self.assertEqual(sum(anchor[16:]) % 256, 0)
                        size, address = struct.unpack_from("<HI", anchor, 22)
                        self.assert_tables(anchor, vm.read_memory(address, size), 2)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qemu", default="qemu-system-x86_64")
    parser.add_argument("--bios")
    OPTIONS, remaining = parser.parse_known_args()
    unittest.main(argv=[__file__, *remaining])
