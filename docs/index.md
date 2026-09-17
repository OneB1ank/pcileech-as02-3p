# Documentation index

This index routes build, hardware, host-integration, and engineering-reference
work. Read only the topic needed for the current task.

## Getting started

- [Build and test](build-and-test.md) — Vivado build outputs and focused regression commands. Read before creating an FPGA image or running local tests.

## Hardware

- [Vivado programming](vivado-programming.md) — JTAG-chain recovery, normal/debug BIT loading, SPIx4 MCS generation, single MT25QU256 programming, power-cycle boot, and PCIe re-enumeration. Read before loading an image onto the board.
- [Board bring-up](board-bringup.md) — ordered PCIe, SFP1, RawUDP, and LeechCore acceptance gates. Read while collecting real-board evidence.

## Host integration

- [LeechCore adapter](leechcore-adapter.md) — build, deployment, plain `fpga` defaults, and mock-versus-hardware test boundaries. Read when integrating a VMM or another LeechCore consumer.

## Engineering reference

- [Architecture](architecture.md) — data paths, clock domains, PCIe format boundaries, and the asmcehnk reuse rule. Read before changing RTL interfaces.
- [Upstream projects and provenance](upstream-and-provenance.md) — PCILeech-FPGA, NeTV2, AMDUSB4, Taxi, Corundum, and LeechCore roles, links, pinned revisions, exclusions, and licenses. Read before changing dependency or attribution text.
- [Validation status](validation.md) — passed evidence and remaining hardware work. Read before making a readiness claim.
- [Migration plan](migration-plan.md) — detailed historical engineering record. Read when tracing migration decisions or unfinished compatibility work.
