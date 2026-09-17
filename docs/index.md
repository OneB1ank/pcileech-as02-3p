# Documentation index

This index routes build, hardware, host-integration, and engineering-reference
work. Read only the topic needed for the current task.

## Getting started

- [Build and test](build-and-test.md) — Vivado build outputs and focused regression commands. Read before creating an FPGA image or running local tests.

## Hardware

- [Vivado programming](vivado-programming.md) — normal/debug image selection, Hardware Manager JTAG programming, PCIe re-enumeration, and the QSPI boundary. Read before loading an image onto the board.
- [Board bring-up](board-bringup.md) — ordered PCIe, SFP1, RawUDP, and LeechCore acceptance gates. Read while collecting real-board evidence.

## Host integration

- [LeechCore adapter](leechcore-adapter.md) — build, deployment, plain `fpga` defaults, and mock-versus-hardware test boundaries. Read when integrating a VMM or another LeechCore consumer.

## Engineering reference

- [Architecture](architecture.md) — data paths, clock domains, PCIe format boundaries, and the asmcehnk reuse rule. Read before changing RTL interfaces.
- [Validation status](validation.md) — passed evidence and remaining hardware work. Read before making a readiness claim.
- [Migration plan](migration-plan.md) — detailed historical engineering record. Read when tracing migration decisions or unfinished compatibility work.
