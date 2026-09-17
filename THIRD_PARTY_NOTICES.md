# Third-party notices

This repository combines original migration work with separately licensed upstream components.

- **asmcehnk / PCILeech lineage** — portions of `as02_asmcehnk_25g/src/` retain Ulf Frisk copyright notices. The repository is distributed under GPL-3.0 unless a file states another license.
- **LeechCore** — git submodule `LeechCore/`, GPL-3.0. The AS02 patch and builder are published with the corresponding source in this repository.
- **Taxi** — git submodule `third_party/taxi/`, CERN-OHL-S-2.0. Files copied and adapted from the AS02 shell retain their own headers; `fpga.sv` and `fpga_core.sv` identify their MIT terms.
- **Corundum** — git submodule `third_party/corundum/`, BSD-style license retained upstream. The Vivado generator selects only the minimal Ethernet/ARP/IPv4/UDP and AXIS dependencies.
- **AMD/Xilinx Vivado IP** — `.xci` and `.coe` files describe project IP configuration. Vivado, generated HDL/netlists, and device support are governed by AMD/Xilinx terms and are not relicensed by this repository.

Each submodule contains its authoritative license text. Preserve existing file headers and notices when redistributing or modifying this project.
