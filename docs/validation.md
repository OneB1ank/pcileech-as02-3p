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
| Hardware gate | A recorded board/NIC/Root Complex command demonstrates the named function | Any later gate that was not exercised |

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

## Open hardware gates

- PCIe cold-boot enumeration and negotiated link evidence.
- BAR0 read/write against a real root complex.
- RQ/RC DMA read/write against host memory.
- Physical SFP1 ARP/UDP capture and reset/relink behavior.
- Plain `fpga` LeechCore/VMM session with the AS02 DLL.
- Sustained 25G traffic, counter correlation, and long-duration stability.

The repository therefore represents a routed and simulated release candidate, not a completed physical-board certification.

## Claim rules

- Seeing `xcku3p_0` in Hardware Manager proves JTAG visibility only.
- Successful FPGA programming proves configuration only.
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
