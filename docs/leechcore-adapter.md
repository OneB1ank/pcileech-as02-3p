# LeechCore adapter

The repository includes a pinned upstream LeechCore submodule and a small, reproducible patch at `as02_asmcehnk_25g/host/leechcore/as02_default_udp.patch`.

## Behavior

When compiled with `AS02_DEFAULT_RAWUDP`, a plain `fpga` device string selects the RawUDP endpoint `192.168.0.222:28474`. Explicit `ip=`, FT601, custom-driver, and FT2232H selections retain their upstream behavior.

This keeps existing applications that hard-code `fpga` compatible with the SFP1 transport. It does not alter the internal 128-bit raw-TLP contract.

## Build

```powershell
cd .\as02_asmcehnk_25g\host\leechcore
.\build_as02_leechcore.ps1
```

The builder creates a detached worktree from the pinned submodule commit, applies the patch, injects the default endpoint definitions, builds the DLL, and emits a manifest containing source, patch, and binary hashes. The upstream submodule itself remains clean.

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
