# Build and test

## Dependencies

- Windows PowerShell 5.1 or PowerShell 7.
- Vivado 2024.2 with `xcku3p-ffvb676-2-e` device support.
- Python 3.
- Visual Studio/MSBuild with the x64 C/C++ toolset for the optional LeechCore DLL.
- Erie/verilog-generator and SynthPilot are recommended for RTL review but are not build-time source dependencies.

Clone with submodules. Taxi, Corundum, and LeechCore are pinned to known commits through gitlinks.

## Vivado build

From `as02_asmcehnk_25g/`:

```powershell
$env:AS02_PROJECT_DIR = Join-Path $PWD '.build\release'
vivado -mode batch -source .\vivado_build.tcl -notrace
```

The generator imports the source-controlled PCIe4 XCI, reusable FIFO/BRAM XCI files, Taxi RTL/Tcl, and the minimal Corundum network files. It removes unused standard-latency PHY IP before implementation.

## Regression groups

On a fresh clone, run the Vivado build before the complete PCIe regression. The
generated-XCI integration case consumes the KU3P-retargeted FIFO/BRAM simulation
netlists produced by IP synthesis. The behavioral PCIe cases can be run earlier,
but the final integration marker requires those generated netlists.

- `run_as02_pcie_tests.ps1`: CQ/CC/RQ/RC conversion, raw-128 compatibility, flow control, tags, sequences, malformed/unsupported handling.
- `run_as02_udp_tests.ps1`: ARP/IPv4/UDP, wire byte order, packetization, CDC, backpressure, and resets.
- `run_as02_framework_tests.ps1`: reused FIFO/mux command and config behavior.
- `run_as02_pcie_profile_tests.ps1`: source-controlled XCI/profile consistency.
- `tests/test_transport_identity_reuse.ps1`: SFP policy, PCIe identity, LeechCore patch, and reuse hashes.

GitHub Actions runs the host-only unit test and source audit. Vivado regressions require a local licensed installation.
