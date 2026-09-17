# Validation status

Validation is divided into evidence levels so a successful source audit or
simulation is not mistaken for physical-board acceptance.

## Evidence model

| Level | What it proves | What it does not prove |
| --- | --- | --- |
| Source/provenance audit | Active source roots, reuse hashes, SFP policy, profile identity and submodule pins match the repository contract | RTL behavior or hardware operation |
| Behavioral/XSim regression | Directed packet, reset, byte-order, descriptor, FIFO and backpressure cases behave as expected in simulation | Timing closure, analog link quality or Root Complex behavior |
| Vivado implementation | The selected part/top synthesizes, places, routes, passes the project timing gate and produces a bitstream | PCIe enumeration, optical traffic or LeechCore operation on a board |
| Host mock | The AS02 LeechCore DLL selects RawUDP, exposes expected APIs, emits MRd/MWr and accepts deterministic completions | Physical SFP1, target PCIe link or real host memory access |
| Hardware gate | A recorded JTAG/Flash/board/NIC/Root Complex command demonstrates the named function | Any later gate that was not exercised |

Every result should bind the source commit, commands, exit codes, tool versions,
testbench or physical setup, literal marker/output, and relevant artifact
hashes. See [Board bring-up](board-bringup.md) for the hardware evidence order.

## Closed in simulation and implementation

Implementation snapshot: 2026-09-04, source snapshot `fc2cc50c4c63bdeaa2da6fdac724b44a9f8616b1`.
The clean public-release tree was revalidated on 2026-09-17 with Vivado 2024.2,
Python 3, Windows PowerShell 5.1, PowerShell 7, and MSBuild 18.10.

- PCIe integration XSim: PASS.
- SFP1 UDP/CDC XSim: PASS.
- Reused asmcehnk framework compatibility: PASS.
- PCIe XCI/profile consistency: PASS.
- RawUDP host mock: PASS.
- Windows PowerShell 5.1 and PowerShell 7 evidence checks: PASS.
- LeechCore x64 patch/build, plain-`fpga` RawUDP mock, and API/TLP mock: PASS.
- Vivado 2024.2 routed implementation: PASS for `xcku3p-ffvb676-2-e`.
- Routed timing: WNS `+0.018 ns`, TNS `0`, WHS `+0.010 ns`, THS `0`.
- Routed DRC errors: `0`; routing errors: `0`.

The principal closed behaviors are:

- the inherited command/FIFO/mux/config framework matches its compatibility
  vectors and content-locked source hashes;
- SFP1 ARP/IPv4/UDP RX/TX, port filtering, byte order, response packetization,
  CDC, reset and backpressure pass focused simulation;
- PCIe CQ/CC and RQ/RC adapters pass raw-128/256 conversion vectors including
  reads, writes, completions, tags, multi-beat packets and backpressure;
- the PCIe profile and checked-in XCI agree on the tracked endpoint envelope;
- the LeechCore patch produces the same initial probe for plain `fpga` and an
  explicit endpoint in the mock environment;
- routed implementation reaches the recorded timing result for the intended
  KU3P part.

## Current bench observation

On **September 17, 2026**, the local Vivado Hardware Manager detected the
programmer/target but did not list `xcku3p_0`. The current physical state is
therefore:

| Hardware evidence item | Historical external diagnostic, August 26, 2026 | Current project acceptance, September 17, 2026 |
| --- | --- | --- |
| Programmer/hardware target visible | OBSERVED | OBSERVED |
| FPGA `xcku3p_0` visible in JTAG chain | OBSERVED | OPEN |
| External Corundum image / cfgmem path | Erase and Program/Verify PASS | diagnostic only; current reproduction optional |
| Historical cfgmem capacity mapping | `Size 256M`, end `0x0FFFFFFF` from old `-size 256` | REJECTED for MT25QU256 release use |
| Post-`boot_hw_device` JTAG configuration status | `DONE_PIN=1`, `ISC_DONE=1` | historical diagnostic only |
| Project normal BIT volatile programming | not part of this evidence | OPEN |
| Project normal BIT → 32 MiB MCS generation | not part of this evidence | OPEN |
| Correct 32 MiB MCS Erase/Program/Verify | not part of this evidence | OPEN |
| Full power removal and automatic project-image boot | not demonstrated | OPEN |

The current observation does not contradict the routed implementation or the
older external diagnostic. At present there is no FPGA device in the JTAG chain
on which either the external baseline or the project image can be re-tested.

The board configuration memory has been identified as one Micron MT25QU256,
256 Mbit, single-device QSPI x4. Vivado 2024.2 on the build workstation contains
both `mt25qu256-spi-x1_x2_x4` and `mt25qu256-qspi-x4-single` catalog entries.
The first is the preferred selection; dual-stacked, dual-parallel/x8, BPI, and
different-capacity entries are excluded.

The corrected `write_cfgmem -size 32` recipe was validated offline with the
external diagnostic BIT: Vivado reported `Size 32M`, end address `0x01FFFFFF`,
generated MCS/PRM, and reported zero warnings/errors. No project release MCS was
programmed by that command validation.

Hardware Manager state and hardware persistence are tracked separately:

| Item | State type | Meaning |
| --- | --- | --- |
| `hw_server`, target and JTAG frequency | Vivado session | Reconnect/reselect after a new session |
| `xcku3p_0` current device | Vivado session plus live JTAG scan | Must be rediscovered before programming |
| BIT and LTX file association | Vivado session | Must match the intended normal/debug build |
| `hw_cfgmem`, MT25QU256 part and MCS/PRM association | Vivado session | Recreate/reselect before another Flash operation |
| FPGA SRAM configuration | Volatile hardware | Lost on power-off or reconfiguration |
| MT25QU256 programmed bytes | Persistent hardware | Remain until erased/reprogrammed |
| `boot_hw_device` result | Commanded warm reload evidence | Not equivalent to physical power removal |
| Autonomous boot after power removal | Persistent-boot evidence | Required before closing the Flash boot gate |

## Open hardware gates

- Restore the JTAG chain so `xcku3p_0` is visible.
- Temporarily program the external known-good BIT, then the project normal BIT.
- Generate a 32 MiB (256 Mbit) SPIx4 MCS at address `0x00000000` with Vivado
  `write_cfgmem -size 32`.
- Complete MT25QU256 Erase/Program/Verify.
- Confirm automatic FPGA configuration after a full power cycle.
- PCIe cold-boot enumeration and negotiated link evidence.
- BAR0 read/write against a real root complex.
- RQ/RC DMA read/write against host memory.
- Physical SFP1 ARP/UDP capture and reset/relink behavior.
- Plain `fpga` LeechCore/VMM session with the AS02 DLL.
- Sustained 25G traffic, counter correlation, and long-duration stability.

The repository therefore represents a routed and simulated release candidate, not a completed physical-board certification.

## Claim rules

- Seeing only the programmer proves the USB/programmer target is reachable; it
  does not prove the FPGA is present in the JTAG chain.
- Seeing `xcku3p_0` in Hardware Manager proves JTAG visibility only.
- Successful FPGA programming proves configuration only.
- Flash Verify proves read-back of programmed contents, not automatic boot.
- Automatic boot after power-cycle proves persistent configuration, not PCIe,
  SFP1, BAR/DMA, or LeechCore behavior.
- A PCIe device entry proves enumeration only after its identity, BAR and link
  properties are recorded.
- An SFP module LED or carrier state proves neither ARP nor UDP payload
  compatibility.
- `AS02_SFP1_NETWORK_TEST_PASS` covers the scripted network checks, not PCIe
  BAR/DMA.
- A LeechCore mock PASS covers the host contract, not the physical board.
- A plain-`fpga` VMM session is a hardware milestone only when the AS02 DLL,
  SFP1 capture, PCIe evidence and image/source hashes are recorded together.

## Traceability

- Runtime data paths and invariants: [Architecture](architecture.md).
- Source roles and upstream links:
  [Upstream projects and provenance](upstream-and-provenance.md).
- Reproducible build and regression commands: [Build and test](build-and-test.md).
- JTAG image selection and PCIe re-enumeration:
  [Vivado programming](vivado-programming.md).
- Ordered physical tests and evidence capture: [Board bring-up](board-bringup.md).
- Host DLL behavior and mock boundary: [LeechCore adapter](leechcore-adapter.md).
- Historical implementation decisions and detailed evidence record:
  [Migration plan](migration-plan.md).
