# Build and test

The build is a source-controlled Vivado Tcl flow. Tcl constructs the project,
imports the exact XCI/RTL/XDC set, synthesizes IP and RTL, implements the design,
checks timing, and only then writes the programming image. GNU Make is not part
of the authoritative AS02 flow.

For the reason each upstream source is present, read
[Upstream projects and provenance](upstream-and-provenance.md).

## Dependencies

- Windows PowerShell 5.1 or PowerShell 7.
- Vivado 2024.2 with `xcku3p-ffvb676-2-e` device support.
- Python 3.
- Visual Studio/MSBuild with the x64 C/C++ toolset for the optional LeechCore DLL.
- Erie/verilog-generator and SynthPilot are recommended for RTL review but are not build-time source dependencies.

Clone with submodules. Taxi, Corundum, and LeechCore are pinned to known commits through gitlinks.

```powershell
git clone --recurse-submodules https://github.com/OneB1ank/pcileech-as02-3p.git
cd pcileech-as02-3p
git submodule status
```

If an existing clone has empty submodule directories, run
`git submodule update --init --recursive` before starting Vivado.

## Build source model

`vivado_generate_project_as02.tcl` is the source-of-truth for the active build:

1. It selects `xcku3p-ffvb676-2-e` and `asmcehnk_as02mc04_top`.
2. It loads the AS02 top, adapted Taxi shell, reusable asmcehnk framework, and
   UltraScale+ PCIe/25G boundary RTL.
3. It imports Taxi 25G MAC/GTY, async FIFO, reset/signal, I2C and related Tcl.
4. It imports only Corundum's generic Ethernet/ARP/IPv4/UDP and AXIS helpers.
5. It loads source-controlled FIFO/BRAM/DROM and PCIe4 XCI/COE inputs.
6. It validates the PCIe XCI against the project PCIe profile so GUI drift does
   not silently change VID/DID/class/BAR/capability settings.

Generated HDL, synthesis products, implementation runs, reports, bitstreams and
probe files remain build artifacts. They are not alternative source roots.

## Vivado build

From `as02_asmcehnk_25g/`:

```powershell
$env:AS02_PROJECT_DIR = Join-Path $PWD '.build\release'
vivado -mode batch -source .\vivado_build.tcl -notrace
```

The generator imports the source-controlled PCIe4 XCI, reusable FIFO/BRAM XCI files, Taxi RTL/Tcl, and the minimal Corundum network files. It removes unused standard-latency PHY IP before implementation.

The normal flow executes these gates in order:

```text
project generation -> IP generation -> synthesis -> implementation
-> routed timing/CDC/methodology reports -> timing gate -> BIT/BIN output
```

Negative setup or hold slack blocks the final `write_bitstream` step. A
bitstream therefore records that this flow reached timing closure, but it does
not replace real PCIe/SFP1 functional testing.

With the example `AS02_PROJECT_DIR`, the normal programming outputs are:

- `.build/release/fpga.runs/impl_1/fpga.bit`
- `.build/release/fpga.runs/impl_1/fpga.bin`

The project is `.build/release/fpga.xpr`. For an ILA-enabled build, run
`vivado -mode batch -source .\vivado_build_debug_as02.tcl -notrace`; it writes
`fpga_debug.bit`, `fpga_debug.bin`, and `fpga_debug.ltx` in
`as02_asmcehnk_25g/`. Continue with [Vivado programming](vivado-programming.md)
to choose and load the correct image.

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

The groups intentionally test separate boundaries:

- **framework compatibility** detects accidental changes to the inherited
  command/FIFO/mux/config behavior;
- **PCIe adapter tests** prove descriptor/raw-TLP conversion without requiring a
  physical Root Complex;
- **UDP tests** prove ARP/IP/UDP parsing, byte order, packet boundaries, CDC and
  backpressure without requiring optical hardware;
- **profile tests** keep the human-readable PCIe profile and XCI synchronized;
- **source/reuse audits** detect SFP1/SFP2 policy drift, unexpected source roots,
  identity drift, or changes to content-locked framework files;
- **LeechCore mocks** verify the host DLL and RawUDP/TLP contract independently
  of the board.

Recommended order on a fresh checkout:

```powershell
cd .\as02_asmcehnk_25g
.\run_as02_pcie_profile_tests.ps1
.\run_as02_framework_tests.ps1
.\run_as02_udp_tests.ps1
python -m unittest -v tests.test_as02_udp_stress
pwsh -File .\tests\test_transport_identity_reuse.ps1

$env:AS02_PROJECT_DIR = Join-Path $PWD '.build\release'
vivado -mode batch -source .\vivado_build.tcl -notrace

.\run_as02_pcie_tests.ps1
```

The final PCIe integration marker is run after IP synthesis because it consumes
the KU3P-retargeted FIFO/BRAM simulation products.

GitHub Actions runs the host-only unit test and source audit. Vivado regressions require a local licensed installation.

Passing GitHub Actions means the public source and host-only checks are healthy;
it does not state that Vivado implementation or a physical board was exercised
by the hosted runner. See [Validation status](validation.md) for evidence levels.
