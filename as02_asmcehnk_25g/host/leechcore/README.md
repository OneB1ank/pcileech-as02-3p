# AS02 LeechCore host adapter

This optional AS02 convenience build keeps the legacy host device string as
plain `fpga` and selects the AS02 RawUDP endpoint by default. Existing host
software can keep its hard-coded `fpga` value without adding a URI or IP
parameter. The explicit form `fpga://ip=HOST,bdf=BDF` remains available as a
diagnostic/override path when a host needs non-default parameters.

## Build

```powershell
.\build_as02_leechcore.ps1 -MsBuildPath "<path-to-MSBuild.exe>"
```

The output directory contains:

- `leechcore.dll` — deployment name expected by existing host applications;
- `leechcore_as02_rawudp_x64.dll` — hashable build-specific copy;
- `as02_leechcore_manifest.json` — source commit, patch hash, endpoint and DLL hash.

Copy `leechcore.dll` beside the host executable (matching x64/x86/ARM64 to the
host process). The application continues to pass exactly:

```text
fpga
```

The default endpoint is `192.168.0.222:28474`. The diagnostic form remains
available as `fpga://ip=HOST`. A PCIe BDF uses numeric form, for example
`03:00.0` is `bdf=0x0300`; the dotted string itself is not a numeric value.
Explicit `ft601=1`, `driver=1`, or `ft2232h=...` parameters retain the
upstream transport selection.

## Transport NIC versus FPGA PCIe endpoint

The controller-side physical 25G NIC and the FPGA PCIe endpoint are two
independent interfaces. The NIC address below is an optional example source
address, not a requirement and not the PCIe identity. If the physical 25G NIC
is installed in another host, that host owns the address; if the NIC is not
installed yet, no address needs to be assigned during PCIe bring-up:

```text
controller 25G NIC (for example 192.168.0.10/24; any unused routed address works)
    <-> LC-LC optics <-> physical SFP1 <-> FPGA 192.168.0.222:28474

FPGA PCIe edge connector
    <-> host root complex <-> independent PF0 VID/DID/class/BAR personality
```

The IPv4 address belongs only to the controller's physical 25G NIC so the
operating system can route ARP/IPv4/UDP packets to SFP1. Do not assign this
address to the FPGA PCIe PF0, and do not use PF0 as the transport NIC. PF0 is
the independent PCIe function used by the host root complex. The current AS02
profile keeps the proven PCILeech VID/DID and BAR envelope (`10EE:0666`, 4 KiB
32-bit BAR, MSI-on/MSI-X-off), while its class is the active AMDUSB4
non-network value `0C0340`. This class-only correction does not change the
SFP1 transport protocol or merge PF0 with the physical NIC. The PF0
personality is controlled separately by
`ip/pcie4_uscale_plus_0_profile.tcl` and the generated XCI.

## Local transport test

```powershell
.\run_as02_leechcore_default_test.ps1 -MsBuildPath "<path-to-MSBuild.exe>"
```

The runner overrides the build IP to `127.0.0.1`, observes both plain and
explicit UDP probes, and writes JSON evidence under `.test_out/`. This is a
host-transport test; live FPGA identity, PCIe BDF, BAR/DRP and DMA remain board
bring-up gates.

## API compatibility mock

The deterministic RawUDP peer below exercises the same exported LeechCore
entry points that a host uses after transport selection:

```powershell
.\run_as02_leechcore_api_test.ps1
```

The runner first produces a loopback-only DLL, then checks `LcCreateEx`, FPGA
identity/version/BDF, `LC_CMD_FPGA_PCIECFGSPACE`, `LC_CMD_FPGA_BAR_INFO`, and
`LC_CMD_FPGA_CFGREGDRP`.  It also issues real `LcReadScatterEx` and `LcWrite`
calls for 32-bit and 64-bit addresses, verifies emitted MRd/MWr TLPs, and feeds
matching CplD packets back through the DLL parser.

The deterministic peer currently uses version `4.13`, FPGA ID `5`, BDF
`03:00.0` (`0x0300`), the current AS02 PCIe profile `10EE:0666`, class
`0C0340`, BAR0 `0x80000000/0x1000`, and the 32-bit non-prefetchable DRP mask
`0xfffff000` as an API parser fixture. The fixture verifies the tracked PF0
metadata contract; it does not make SFP1 a PCIe network function.
The JSON result is written to `.test_out/api_mock_test.json`.  This remains a
host/API contract test; CQ/CC, RQ/RC, physical enumeration, SFP1, and board DMA
require their separate hardware evidence gates.
