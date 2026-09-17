# Validation status

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

## Open hardware gates

- PCIe cold-boot enumeration and negotiated link evidence.
- BAR0 read/write against a real root complex.
- RQ/RC DMA read/write against host memory.
- Physical SFP1 ARP/UDP capture and reset/relink behavior.
- Plain `fpga` LeechCore/VMM session with the AS02 DLL.
- Sustained 25G traffic, counter correlation, and long-duration stability.

The repository therefore represents a routed and simulated release candidate, not a completed physical-board certification.
