// XSim compatibility shim for the legacy AMDUSB4 byte-swap macro.
// Keep the production header and shadow configuration RTL byte-identical.
`undef _bs16
`define _bs16(v) {v[7:0], v[15:8]}
