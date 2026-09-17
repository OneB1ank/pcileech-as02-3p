# Contributing

Keep changes narrow and evidence-driven.

- Preserve the chip-independent asmcehnk framework unless a failing compatibility test proves a required change.
- Keep SFP1 as the sole transport and SFP2 idle unless a separate design change updates documentation and tests.
- Keep internal TLPs raw-128; perform 256-bit conversion only at the UltraScale+ boundary.
- Add or update focused XSim tests for RTL changes.
- Run the transport/reuse audit and relevant Vivado regression before opening a pull request.
- Do not commit Vivado build directories, bitstreams, packet captures, local absolute paths, or hardware evidence containing machine-specific data.
