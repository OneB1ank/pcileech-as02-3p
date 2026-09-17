# LeechCore adapter

The repository includes a pinned upstream LeechCore submodule and a small, reproducible patch at `as02_asmcehnk_25g/host/leechcore/as02_default_udp.patch`.

[LeechCore](https://github.com/ufrisk/LeechCore) is the host-side library used
by PCILeech-compatible applications. The FPGA RTL is not part of LeechCore;
LeechCore produces and consumes the command and raw-TLP payloads transported by
the FPGA design. See [Upstream projects and provenance](upstream-and-provenance.md)
for the relationship to PCILeech-FPGA, NeTV2, Taxi, and Corundum.

## Data-flow principle

```text
host application / VMM
  -> LeechCore API
  -> FPGA device backend
  -> RawUDP datagram on controller 25G NIC
  -> SFP1 UDP/asmcehnk boundary
  -> raw 128-bit TLP and command framework
  -> PCIe CQ/CC/RQ/RC adapters
  -> target Root Complex
```

Replies return through the reverse path. The transport carries the existing
protocol; it does not translate memory operations into a new AS02-specific API.

## Behavior

When compiled with `AS02_DEFAULT_RAWUDP`, a plain `fpga` device string selects the RawUDP endpoint `192.168.0.222:28474`. Explicit `ip=`, FT601, custom-driver, and FT2232H selections retain their upstream behavior.

This keeps existing applications that hard-code `fpga` compatible with the SFP1 transport. It does not alter the internal 128-bit raw-TLP contract.

The default selection occurs in the host DLL, not in Windows network adapter
configuration. The controller NIC still needs a route/interface capable of
reaching `192.168.0.222`; the FPGA PCIe PF0 remains a separate device.

## Build

```powershell
cd .\as02_asmcehnk_25g\host\leechcore
.\build_as02_leechcore.ps1
```

The builder creates a detached worktree from the pinned submodule commit, applies the patch, injects the default endpoint definitions, builds the DLL, and emits a manifest containing source, patch, and binary hashes. The upstream submodule itself remains clean.

Using a detached worktree has two purposes: the published Git submodule stays
at its recorded upstream commit, and every produced DLL can be traced to a
specific upstream hash plus the small AS02 patch and build parameters.

The default output directory is `as02_asmcehnk_25g/host/leechcore/out/`:

- `leechcore.dll` — deployment filename expected by existing applications.
- `leechcore_as02_rawudp_x64.dll` — hashable x64 build artifact.
- `as02_leechcore_manifest.json` — source, patch, endpoint, and DLL hashes.

Copy `leechcore.dll` beside the x64 application executable. A plain `fpga`
device string uses `192.168.0.222:28474`; the diagnostic form
`fpga://ip=192.168.0.222` remains supported.

## Tests

- `run_as02_leechcore_default_test.ps1` proves plain `fpga` and explicit IP forms emit the same initial RawUDP probe.
- `run_as02_leechcore_api_test.ps1` exercises identity, configuration/BAR/DRP APIs, scatter reads, writes, emitted MRd/MWr TLPs, and returned completions against a deterministic mock peer.

These tests validate the host adapter and wire contract against a mock peer.
They do not replace the physical SFP1, PCIe enumeration, BAR/DMA, or sustained
VMM acceptance gates in [Board bring-up](board-bringup.md).

The default-transport test observes the initial UDP probe for both `fpga` and
an explicit loopback IP. The API mock goes further: it responds to identity,
config-space, BAR and DRP commands, observes generated MRd/MWr TLPs, and returns
matching completions. This proves host parsing and packet construction, but the
mock has no physical GTY, PCIe Root Complex, or host memory.
