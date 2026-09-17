# AS02MC04 asmcehnk 25G

Vivado 2024.2 project that ports the asmcehnk/PCILeech-compatible FPGA framework to the AS02MC04 (`XCKU3P-FFVB676-2E`) and replaces the FT601 transport with a 25G RawUDP link on **SFP1**.

> Release status (2026-09-17): RTL integration, focused XSim regression, routed implementation, timing closure, and host-adapter mock tests pass. Physical-board PCIe enumeration, BAR/DMA, SFP1 packet capture, plain `fpga` VMM session, and sustained throughput remain hardware acceptance gates.

## Design rules

- Reuse the chip-independent asmcehnk framework; board-specific changes stay at the AS02, 25G, CDC, and UltraScale+ PCIe boundaries.
- **SFP1 / RTL lane 0** is the only RawUDP transport. **SFP2 / lane 1** is TX-idle and RX-drain.
- Internal PCIe packets remain 128-bit raw TLPs. The 256-bit format exists only at the UltraScale+ CQ/CC/RQ/RC boundary.
- The PCIe endpoint and the controller-side 25G NIC are independent. The NIC address is only for ARP/IPv4/UDP transport.
- Vivado Tcl is the authoritative build flow; GNU Make is not required.

## Based on and referenced projects

This repository combines several projects at different boundaries; it is not an
unchanged fork of any one of them.

| Project | Role in this port |
| --- | --- |
| [PCILeech-FPGA](https://github.com/ufrisk/pcileech-fpga) | FPGA/raw-TLP protocol lineage and PCIe profile reference. |
| [NeTV2](https://github.com/ufrisk/pcileech-fpga/tree/master/NeTV2) | RawUDP wire-format and host-behavior reference; its RMII/A7 board design is not used. |
| Local AMDUSB4/asmcehnk snapshot | Functional baseline for the preserved FIFO/mux/BAR/config-shadow/raw-128 framework. |
| [Taxi AS02MC04](https://github.com/fpganinja/taxi/tree/master/src/cndm/board/AS02MC04/fpga) | AS02 board shell, constraints, clocks, GTY, 25G MAC/PHY, I2C and CDC helpers. |
| [Corundum](https://github.com/corundum/corundum) and [Nexus K3P-S 25G](https://github.com/corundum/corundum/tree/master/fpga/mqnic/Nexus_K3P_S/fpga_25g) | Minimal generic Ethernet/ARP/IPv4/UDP RTL plus KU3P/25G design reference; mqnic/DMA is not imported. |
| [LeechCore](https://github.com/ufrisk/LeechCore) | Host-side API and RawUDP transport selection. |

See [Upstream projects and provenance](docs/upstream-and-provenance.md) for
pinned revisions, reused modules, excluded subsystems, licenses, and the exact
boundary between inherited and project-specific work.

## Repository layout

- `as02_asmcehnk_25g/src/` — top-level RTL, UDP transport, PCIe adapters, reused framework.
- `as02_asmcehnk_25g/ip/` — source-controlled XCI/COE and PCIe profile.
- `as02_asmcehnk_25g/tests/` — focused PCIe, UDP, framework, and host-contract tests.
- `as02_asmcehnk_25g/host/leechcore/` — reproducible LeechCore RawUDP patch, builder, and API tests.
- `third_party/taxi/` — AS02 shell, clocks, GTY, MAC/PHY dependency.
- `third_party/corundum/` — minimal Ethernet/ARP/IPv4/UDP RTL dependency.
- `LeechCore/` — pinned upstream host library consumed by the AS02 patch flow.
- `docs/` — architecture, build, board bring-up, validation, and migration detail.

## Clone

```powershell
git clone --recurse-submodules https://github.com/OneB1ank/pcileech-as02-3p.git
cd pcileech-as02-3p
```

## Build the FPGA image

Requirements: Vivado 2024.2 with the Kintex UltraScale+ device files installed.

```powershell
cd .\as02_asmcehnk_25g
$env:AS02_PROJECT_DIR = Join-Path $PWD '.build\release'
vivado -mode batch -source .\vivado_build.tcl -notrace
```

The bitstream is generated below the selected project directory in `fpga.runs/impl_1/`. Timing failure blocks bitstream generation.

The release image is written to
`as02_asmcehnk_25g/.build/release/fpga.runs/impl_1/fpga.bit`. See
[Build and test](docs/build-and-test.md) for the regression groups and
[Vivado programming](docs/vivado-programming.md) before loading the image.

## Build the modified LeechCore adapter

The upstream LeechCore tree remains a pinned submodule. `host/leechcore/as02_default_udp.patch` changes only the default transport selection so a plain `fpga` device string selects `192.168.0.222:28474`; explicit FT601/driver parameters remain available.

```powershell
cd .\as02_asmcehnk_25g\host\leechcore
.\build_as02_leechcore.ps1
.\run_as02_leechcore_default_test.ps1
.\run_as02_leechcore_api_test.ps1
```

Deploy the produced `leechcore.dll` beside the x64 host application. Existing
applications may continue using `-device fpga`. See
[LeechCore adapter](docs/leechcore-adapter.md) for outputs, tests, and the
real-hardware boundary.

## Documentation map

The main README is intentionally brief. Start with the topic needed for the
current task, or use the complete [documentation index](docs/index.md).

| Topic | Purpose |
| --- | --- |
| [Build and test](docs/build-and-test.md) | Create normal/debug images and run focused regression groups. |
| [Vivado programming](docs/vivado-programming.md) | Recover the JTAG chain, load BIT/LTX, generate SPIx4 MCS, program the single MT25QU256, and verify power-cycle boot. |
| [Board bring-up](docs/board-bringup.md) | Execute the ordered PCIe → SFP1 → RawUDP → LeechCore hardware gates. |
| [LeechCore adapter](docs/leechcore-adapter.md) | Build/deploy the DLL and use plain `fpga` with the default RawUDP endpoint. |
| [Architecture](docs/architecture.md) | Understand reuse boundaries, clock domains, and 128/256-bit PCIe adaptation. |
| [Upstream projects and provenance](docs/upstream-and-provenance.md) | See which projects supplied code, behavior, board knowledge, or host contracts. |
| [Validation status](docs/validation.md) | Separate completed simulation/build evidence from open physical-board gates. |
| [Migration plan](docs/migration-plan.md) | Read the detailed historical migration and compatibility record. |

## Licensing

Unless a file states otherwise, this repository is released under GPL-3.0. Files retaining MIT or other notices remain under those notices. Submodules retain their upstream licenses. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Xilinx/AMD Vivado and generated IP outputs remain subject to their vendor terms.
