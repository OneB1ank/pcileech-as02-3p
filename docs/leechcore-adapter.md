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

## Tests

- `run_as02_leechcore_default_test.ps1` proves plain `fpga` and explicit IP forms emit the same initial RawUDP probe.
- `run_as02_leechcore_api_test.ps1` exercises identity, configuration/BAR/DRP APIs, scatter reads, writes, emitted MRd/MWr TLPs, and returned completions against a deterministic mock peer.
