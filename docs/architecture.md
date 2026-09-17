# Architecture

## Data planes

```text
controller 25G NIC
  <-> SFP1 / Taxi GTY + 25G MAC
  <-> Corundum Ethernet + ARP + IPv4 + UDP (64-bit AXIS)
  <-> IfComToFifo (64-bit RX / 256-bit TX)
  <-> reused asmcehnk FIFO and mux
  <-> reused BAR, config-shadow, and raw-128 TLP framework
  <-> AS02 UltraScale+ adapters
  <-> PCIe4 CQ/CC/RQ/RC (256-bit at the hard-IP boundary)
```

The physical 25G NIC is a controller transport interface. It does not define the PCIe class or make the FPGA endpoint a network adapter.

## Port policy

- SFP1 maps to `sfp_rx/tx[0]` and is the sole transport.
- SFP2 maps to `sfp_rx/tx[1]`; its TX valid is held low and RX is continuously drained.

## Reuse boundary

The project intentionally preserves the chip-independent framework. Byte-identical reuse is recorded in `as02_asmcehnk_25g/reuse_manifest.json`. Migration-specific RTL is concentrated in the AS02 top, UDP boundary, CDC staging, and UltraScale+ PCIe adapters.

## Clock domains

- PCIe user clock: 250 MHz.
- SFP1 MAC/network domain: derived from the 25G GTY path.
- Board/system control domains: Taxi shell clocks.

Frame CDC and reset synchronization are explicit. Generated PCIe and inherited Taxi GT reset structures remain visible in the CDC report rather than being hidden with waivers.
