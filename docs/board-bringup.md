# Board bring-up

Use the gates in order and retain evidence from each gate. A later gate does not imply that an earlier gate passed.

## 1. Program and enumerate

- Follow [Vivado programming](vivado-programming.md) to choose a normal or debug
  image, associate a matching LTX when required, and program `xcku3p_0` through
  JTAG.
- For reliable cold enumeration, keep the FPGA configured before or during host
  reset. A Device Manager refresh alone may not retrain and re-enumerate the
  endpoint.
- Confirm the endpoint, negotiated width/rate, BAR0, and configuration capabilities.

The tracked PCIe profile is `10EE:0666`, class `0C0340`, 4 KiB 32-bit BAR0, MSI enabled, MSI-X disabled.

## 2. Connect SFP1

Connect a 25G controller NIC to physical SFP1 with compatible SFP28 modules and LC-LC fiber. SFP2 is not a transport port.

Assign the controller NIC an unused address in the FPGA endpoint subnet, for example `192.168.0.10/24`. This address belongs only to the controller NIC.

```powershell
New-NetIPAddress -InterfaceAlias '<25G NIC>' -IPAddress 192.168.0.10 -PrefixLength 24
cd .\as02_asmcehnk_25g
.\test_as02_sfp1.ps1 -InterfaceAlias '<25G NIC>' -StressIterations 1000
```

Expected marker: `AS02_SFP1_NETWORK_TEST_PASS`. The test verifies 25G link state, ARP MAC `02:00:00:00:00:de`, register probe, loopback, stress/rejection behavior, and NIC error counters.

## 3. LeechCore/VMM

Build or copy the AS02 `leechcore.dll` beside the x64 host application. Continue using the device string `fpga`; the AS02 build defaults it to RawUDP `192.168.0.222:28474`.

Start with identity and a small read, then progress to repeated reads/writes and sustained traffic. Record host output and packet captures.

See [LeechCore adapter](leechcore-adapter.md) for the builder outputs, deployment
layout, default/explicit device strings, and mock-test boundary.

## 4. Evidence

```powershell
.\collect_as02_evidence.ps1 -InterfaceAlias '<25G NIC>' -CaptureSeconds 60
```

For debug images, also supply matching `.bit`, `.ltx`, ILA CSV, and stimulus logs. A complete acceptance set includes PCIe enumeration, SFP1 pcapng, NIC before/after counters, source commit, image hashes, and host commands.
