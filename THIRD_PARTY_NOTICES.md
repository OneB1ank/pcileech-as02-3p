# Third-party notices

This repository combines original migration work with separately licensed
upstream components and reference designs.

- **PCILeech-FPGA / asmcehnk lineage** —
  [upstream project](https://github.com/ufrisk/pcileech-fpga). Portions of
  `as02_asmcehnk_25g/src/` retain Ulf Frisk copyright notices. The repository
  root is distributed under GPL-3.0 unless a file states another license.
- **NeTV2** —
  [reference directory](https://github.com/ufrisk/pcileech-fpga/tree/master/NeTV2)
  inside PCILeech-FPGA. It was used for RawUDP behavior and wire-format study;
  its board top, RMII/FC1003 path, constraints, and generated IP are not active
  dependencies.
- **AMDUSB4/asmcehnk local baseline** — the migration used a local source
  snapshot whose public upstream URL and release were not verified. Reused
  content is recorded by `as02_asmcehnk_25g/reuse_manifest.json`; this notice
  does not assign an invented upstream identity to that snapshot.
- **LeechCore** — [upstream project](https://github.com/ufrisk/LeechCore), GPL-3.0,
  git submodule `LeechCore/`. The AS02 patch and builder are published with the
  corresponding source in this repository.
- **Taxi** — [upstream project](https://github.com/fpganinja/taxi),
  CERN-OHL-S-2.0, git submodule `third_party/taxi/`. The
  [AS02MC04 reference](https://github.com/fpganinja/taxi/tree/master/src/cndm/board/AS02MC04/fpga)
  supplied board-shell material. Copied/adapted files retain their headers;
  `fpga.sv`, `fpga_core.sv`, and the copied XDC sections identify MIT terms.
- **Corundum** — [upstream project](https://github.com/corundum/corundum),
  BSD-style license retained upstream, git submodule `third_party/corundum/`.
  The Vivado generator selects only minimal Ethernet/ARP/IPv4/UDP and AXIS
  dependencies. The
  [Nexus K3P-S 25G design](https://github.com/corundum/corundum/tree/master/fpga/mqnic/Nexus_K3P_S/fpga_25g)
  is a device/25G reference; its mqnic core, DMA, driver, and top are not used.
- **AMD/Xilinx Vivado IP** — `.xci` and `.coe` files describe project IP
  configuration. Vivado, generated HDL/netlists, and device support are governed
  by AMD/Xilinx terms and are not relicensed by this repository.

Each submodule contains its authoritative license text. Preserve existing file headers and notices when redistributing or modifying this project.

See [Upstream projects and provenance](docs/upstream-and-provenance.md) for the
technical relationship between these sources. Listing a project here describes
provenance and licensing, not endorsement or official compatibility approval.
