# AS02MC04 asmcehnk 25G

Vivado 2024.2 project that ports the asmcehnk/PCILeech-compatible FPGA framework to the AS02MC04 (`XCKU3P-FFVB676-2E`) and replaces the FT601 transport with a 25G RawUDP link on **SFP1**.

> Release status (2026-09-17): RTL integration, focused XSim regression, routed implementation, timing closure, and host-adapter mock tests pass. Physical-board PCIe enumeration, BAR/DMA, SFP1 packet capture, plain `fpga` VMM session, and sustained throughput remain hardware acceptance gates.

## Design rules

- Reuse the chip-independent asmcehnk framework; board-specific changes stay at the AS02, 25G, CDC, and UltraScale+ PCIe boundaries.
- **SFP1 / RTL lane 0** is the only RawUDP transport. **SFP2 / lane 1** is TX-idle and RX-drain.
- Internal PCIe packets remain 128-bit raw TLPs. The 256-bit format exists only at the UltraScale+ CQ/CC/RQ/RC boundary.
- The PCIe endpoint and the controller-side 25G NIC are independent. The NIC address is only for ARP/IPv4/UDP transport.
- Vivado Tcl is the authoritative build flow; GNU Make is not required.

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

## Run focused tests

```powershell
cd .\as02_asmcehnk_25g
.\run_as02_pcie_tests.ps1
.\run_as02_udp_tests.ps1
.\run_as02_framework_tests.ps1
.\run_as02_pcie_profile_tests.ps1
python -m unittest -v tests.test_as02_udp_stress
pwsh -File .\tests\test_transport_identity_reuse.ps1
```

## Build the modified LeechCore adapter

The upstream LeechCore tree remains a pinned submodule. `host/leechcore/as02_default_udp.patch` changes only the default transport selection so a plain `fpga` device string selects `192.168.0.222:28474`; explicit FT601/driver parameters remain available.

```powershell
cd .\as02_asmcehnk_25g\host\leechcore
.\build_as02_leechcore.ps1
.\run_as02_leechcore_default_test.ps1
.\run_as02_leechcore_api_test.ps1
```

Deploy the produced `leechcore.dll` beside the x64 host application. Existing applications may continue using `-device fpga`.

## Hardware bring-up summary

1. Program the FPGA and cold-boot/rescan the PCIe host.
2. Confirm the endpoint identity, BAR0, link width, and link rate.
3. Connect the controller 25G NIC to physical SFP1 and assign an unused address in `192.168.0.0/24` (for example `192.168.0.10/24`).
4. Run `test_as02_sfp1.ps1 -InterfaceAlias '<25G NIC>'`.
5. Run the host/VMM with the AS02 `leechcore.dll` and plain `fpga`.
6. Archive NIC counters, packet capture, PCIe enumeration, and optional ILA/VIO data with `collect_as02_evidence.ps1`.

See [docs/board-bringup.md](docs/board-bringup.md) for the complete gate sequence.

## Documentation

Start with [docs/index.md](docs/index.md). The detailed historical migration plan is preserved at [docs/migration-plan.md](docs/migration-plan.md).

## Licensing

Unless a file states otherwise, this repository is released under GPL-3.0. Files retaining MIT or other notices remain under those notices. Submodules retain their upstream licenses. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Xilinx/AMD Vivado and generated IP outputs remain subject to their vendor terms.
