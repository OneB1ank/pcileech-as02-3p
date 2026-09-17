# Upstream projects and provenance

This document explains which projects contributed code, behavior, board
knowledge, or host-side contracts to this repository. The design is an
integration of several clearly bounded sources; it is not an unmodified fork of
one upstream project.

## Contents

- [Relationship overview](#relationship-overview)
- [Dependency classes and pinned revisions](#dependency-classes-and-pinned-revisions)
- [PCILeech-FPGA and NeTV2](#pcileech-fpga-and-netv2)
- [Local AMDUSB4 engineering baseline](#local-amdusb4-engineering-baseline)
- [Taxi and the AS02MC04 board shell](#taxi-and-the-as02mc04-board-shell)
- [Corundum and the 25G network stack](#corundum-and-the-25g-network-stack)
- [LeechCore host integration](#leechcore-host-integration)
- [What this repository adds](#what-this-repository-adds)
- [Licensing and project identity](#licensing-and-project-identity)

## Relationship overview

```text
PCILeech-FPGA protocol lineage
  + NeTV2 RawUDP behavior reference
  + local AMDUSB4/asmcehnk functional baseline
                     |
                     v
       preserved 128-bit raw-TLP framework
                     |
       +-------------+----------------+
       |                              |
       v                              v
Taxi AS02 shell/GTY/MAC       UltraScale+ PCIe adapters
       |                       CQ/CC/RQ/RC + cfg_mgmt
       v                              |
Corundum ARP/IPv4/UDP                 |
       |                              |
       +-------- AS02 integration ----+
                     |
                     v
          LeechCore RawUDP host path
```

The controller-side 25G NIC is a transport endpoint. The FPGA's PCIe PF0 is a
separate endpoint presented to a PCIe Root Complex. Network addressing never
defines the PCIe VID/DID/class/BAR personality.

## Dependency classes and pinned revisions

| Source | Relationship | Revision in this repository | Active use |
| --- | --- | --- | --- |
| [Taxi](https://github.com/fpganinja/taxi) | Git submodule | `9d0306eab37406db27afeca3d62a870746f29850` | AS02 board helpers, 25G GTY/MAC, clocks, resets, I2C and AXIS CDC |
| [Corundum](https://github.com/corundum/corundum) | Git submodule | `1ca0151b97af85aa5dd306d74b6bcec65904d2ce` | Generic 64-bit Ethernet/ARP/IPv4/UDP RTL and AXIS helpers |
| [LeechCore](https://github.com/ufrisk/LeechCore) | Git submodule | `709dce874df14e289e1c26fc18ab0b0856ae4151` | Host library patched in a detached worktree for the AS02 default RawUDP endpoint |
| [PCILeech-FPGA](https://github.com/ufrisk/pcileech-fpga) | Protocol/RTL lineage and comparison reference | not a submodule; profile comparison used commit `c538c4170678c13f723dc921905fb81ff3c71d8e` | Raw-TLP, BAR, configuration and FPGA-host contract history |
| [NeTV2](https://github.com/ufrisk/pcileech-fpga/tree/master/NeTV2) | Reference design inside PCILeech-FPGA | not a submodule | RawUDP wire ordering and host interaction reference |
| AMDUSB4/asmcehnk snapshot | Local migration baseline | recorded by `as02_asmcehnk_25g/reuse_manifest.json` | FIFO/mux, BAR, config shadow, raw-128 TLP and project-structure baseline |

The three submodule hashes above are Git links in this repository. The
PCILeech-FPGA commit is a reference point, not a fourth submodule. The local
AMDUSB4 snapshot has no verified public remote or upstream version, so this
project records it as a local engineering baseline rather than inventing a
repository link.

## PCILeech-FPGA and NeTV2

[PCILeech-FPGA](https://github.com/ufrisk/pcileech-fpga) is the public FPGA
project lineage behind the PCILeech-style host/device contract. It supplies the
historical context for the 128-bit raw-TLP representation, command transport,
BAR behavior, configuration-space handling, and PCIe profile comparisons used
during this port.

This repository is not a direct Git fork of the current PCILeech-FPGA master
tree. Compatibility is an engineering target demonstrated by golden vectors,
reuse hashes, XSim cases, and the LeechCore mock; it is not an upstream
certification claim.

[NeTV2](https://github.com/ufrisk/pcileech-fpga/tree/master/NeTV2) is part of the
PCILeech-FPGA tree. It was used to understand the Ethernet/RawUDP transport
contract: command framing, byte order, response segmentation, and the way the
host exchanges existing asmcehnk protocol words over UDP.

The following NeTV2-specific hardware was deliberately not carried into the
AS02 implementation:

- the RMII/FC1003 Ethernet path;
- Artix-7 board top-level and constraints;
- the 7-series PCIe wrapper;
- the low-width transport implementation;
- NeTV2 board clocks, pins, and generated IP.

The AS02 design reproduces the required wire behavior at a new 64-bit 25G AXIS
boundary instead of embedding the NeTV2 board design.

## Local AMDUSB4 engineering baseline

The migration started from a local AMDUSB4/asmcehnk source snapshot. That
snapshot supplied the functional baseline and directory style that the user
wanted preserved. Its public repository provenance was not verified, so it is
described here only by the auditable files included in this repository.

The following chip-independent files are content-locked after UTF-8/LF
normalization in `as02_asmcehnk_25g/reuse_manifest.json`:

- `asmcehnk_header.svh`;
- `asmcehnk_tlps128_bar_controller.sv`;
- `asmcehnk_tlps128_cfgspace_shadow.sv`;
- `asmcehnk_pcie_cfgspace_shadow.sv`.

Content locking records provenance, not necessarily active instantiation. In
the current AS02 build, `asmcehnk_tlps128_cfgspace_shadow.sv` is the active raw
configuration-TLP shadow. `asmcehnk_pcie_cfgspace_shadow.sv` is retained as a
legacy/reference comparison file and is not loaded by
`vivado_generate_project_as02.tcl`.

Other framework modules retain the same protocol role even where an
UltraScale+ connection, reset split, or source-root extraction required a small
integration change. The preserved contract includes:

- command classification and the `IfComToFifo` boundary;
- the command/TLP/config FIFO and mux ordering;
- BAR0 request semantics and completion generation;
- raw 128-bit TLP words and first/last/keep/BAR-hit metadata;
- configuration-space and shadow-register behavior;
- existing host-visible command, loopback, and status layout.

The board-specific parts were replaced rather than forced onto the new FPGA:

- FT601 transport became SFP1 RawUDP;
- 7-series PCIe streaming became UltraScale+ CQ/CC/RQ/RC;
- A7/75T/100T tops, XDC and clocking became AS02/KU3P equivalents;
- `pcie_7x_0` generated logic became a source-controlled PCIe4 UltraScale+ XCI
  and profile.

This boundary is why the internal protocol remains 128-bit even though the
PCIe4 hard-IP interface and transmit packetizer are 256-bit.

## Taxi and the AS02MC04 board shell

The active board dependency is [Taxi](https://github.com/fpganinja/taxi). The
specific board reference is the
[Taxi AS02MC04 design](https://github.com/fpganinja/taxi/tree/master/src/cndm/board/AS02MC04/fpga).

Taxi contributes or informs:

- AS02MC04 PCIe, SFP, I2C, QSPI, clock and reset connectivity;
- the two GTY channel mapping and 25GBASE-R PHY configuration;
- the 25G MAC and its 64-bit AXIS interface;
- asynchronous AXIS frame FIFOs and reset/signal synchronizers;
- SFP management and board-control helpers;
- Vivado Tcl needed to construct the Taxi IP dependencies.

The original Taxi README names `xcku3p-ffvb676-1-e`; this project explicitly
targets `xcku3p-ffvb676-2-e`. The checked-in `fpga.sv`, `fpga_core.sv`, top-level
wrapper, constraints, and Vivado flow are therefore copied/adapted integration
work, not a claim that the Taxi AS02 bitstream is used unchanged.

The complete CNDM application, its Linux driver, its Makefile build, and its
traffic semantics are outside the active design. Taxi provides the physical
board and 25G shell around the asmcehnk core.

## Corundum and the 25G network stack

The active generic network modules come from
[Corundum](https://github.com/corundum/corundum). The Vivado generator imports a
minimal subset from `fpga/lib/eth/rtl` and the associated AXIS library:

- Ethernet AXIS RX/TX;
- ARP and ARP cache;
- IPv4 RX/TX and arbitration;
- UDP RX/TX and checksum generation;
- AXIS adapter, FIFO, arbiter, priority encoder and LFSR helpers.

These modules provide the protocol mechanics. AS02-specific logic supplies the
fixed local MAC/IP/UDP port, peer tracking, destination filtering, command-word
packing, response packetization, and reset/CDC policy.

The
[Corundum Nexus K3P-S 25G project](https://github.com/corundum/corundum/tree/master/fpga/mqnic/Nexus_K3P_S/fpga_25g)
was also reviewed because its K3P-S target is `xcku3p-ffvb676-2-e` and it shows
a complete 25G design on the same device/package class. It is a board/device
reference, not the active top-level design.

The repository does not import Corundum's mqnic core, PCIe DMA engine, queues,
register map, Linux driver, Nexus top-level, or full NIC datapath. The FPGA
endpoint therefore does not become a Corundum network card.

## LeechCore host integration

[LeechCore](https://github.com/ufrisk/LeechCore) is the host-side API and FPGA
transport library. It is not FPGA RTL. The repository keeps it as a pinned
submodule and builds the AS02 DLL from a detached worktree so the upstream
checkout remains clean.

`as02_asmcehnk_25g/host/leechcore/as02_default_udp.patch` changes the plain
`fpga` selection path when `AS02_DEFAULT_RAWUDP` is defined. It makes an
application that already passes `fpga` select `192.168.0.222:28474` by default.
Explicit IP, FT601, driver, and FT2232H options remain available.

The patch does not redefine LeechCore's raw-TLP memory API. The FPGA side must
continue to accept the same command/TLP payloads and return the same responses;
only the physical transport changes from USB/FT601 to SFP1/RawUDP.

## What this repository adds

The AS02 project supplies the integration work that does not exist as a single
upstream design:

- `asmcehnk_as02mc04_top` and the KU3P/FFVB676-2E constraints;
- the SFP1-only port policy and explicit SFP2 idle/drain behavior;
- a 25G Ethernet/ARP/IPv4/UDP wrapper for the asmcehnk command boundary;
- 64-bit RX and 256-bit TX protocol packing compatible with the existing wire
  contract;
- UltraScale+ config-management and CQ/CC/RQ/RC adapters around the preserved
  raw-128 framework;
- CDC/reset staging between PCIe, MAC, and system domains;
- a source-controlled PCIe4 XCI/profile and KU3P-retargeted FIFO/BRAM IP;
- focused XSim regressions, source/reuse audits, board test scripts, and
  evidence collection;
- a reproducible LeechCore AS02 host build.

## Licensing and project identity

The repository root is GPL-3.0 unless an individual file states otherwise.
Submodules retain their own licenses; copied/adapted files retain their headers.
Taxi, Corundum, LeechCore, PCILeech-FPGA, AMD/Xilinx, and this repository remain
separate projects. Links and compatibility statements describe provenance and
interfaces, not endorsement or official upstream support.

See [Third-party notices](../THIRD_PARTY_NOTICES.md) for the concise legal
inventory and [Architecture](architecture.md) for the runtime data paths.
