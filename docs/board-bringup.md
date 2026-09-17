# Board bring-up

Use the gates in order and retain evidence from each gate. A later gate does not imply that an earlier gate passed.

The order isolates the three systems that must work together: FPGA
configuration/PCIe enumeration, the independent SFP1 RawUDP transport, and the
LeechCore memory/TLP API. A link LED or JTAG device by itself covers only one
small part of that chain.

## 0. Preflight

- Use a bitstream whose source commit and SHA-256 are recorded.
- Verify that the controller cable is connected to physical **SFP1**, not SFP2.
- Confirm compatible 25G SFP28 optics/DAC and that the controller NIC supports
  the selected module.
- Keep the target host's PCIe connection conceptually separate from the
  controller NIC/IPv4 connection.
- Use a matching `.ltx` only when the programmed debug `.bit` contains the same
  ILA/VIO build.

The source and project relationships behind these interfaces are documented in
[Architecture](architecture.md) and
[Upstream projects and provenance](upstream-and-provenance.md).

## 1. Program and enumerate

- Follow [Vivado programming](vivado-programming.md) to choose a normal or debug
  image, associate a matching LTX when required, and program `xcku3p_0` through
  JTAG.
- For reliable cold enumeration, keep the FPGA configured before or during host
  reset. A Device Manager refresh alone may not retrain and re-enumerate the
  endpoint.
- Confirm the endpoint, negotiated width/rate, BAR0, and configuration capabilities.

The tracked PCIe profile is `10EE:0666`, class `0C0340`, 4 KiB 32-bit BAR0, MSI enabled, MSI-X disabled.

Why this gate comes first: CQ/CC and RQ/RC depend on a trained PCIe link and a
Root Complex that has assigned bus/device/function and BAR resources. Network
traffic cannot prove that enumeration occurred.

Retain at least:

- Vivado programming result and image hash;
- target-host cold-boot/rescan procedure;
- VID/DID/class, BDF, BAR0 address/size, link width and link speed;
- operating-system enumeration output before and after programming.

## 2. Connect SFP1

Connect a 25G controller NIC to physical SFP1 with compatible SFP28 modules and LC-LC fiber. SFP2 is not a transport port.

Assign the controller NIC an unused address in the FPGA endpoint subnet, for example `192.168.0.10/24`. This address belongs only to the controller NIC.

```powershell
New-NetIPAddress -InterfaceAlias '<25G NIC>' -IPAddress 192.168.0.10 -PrefixLength 24
cd .\as02_asmcehnk_25g
.\test_as02_sfp1.ps1 -InterfaceAlias '<25G NIC>' -StressIterations 1000
```

Expected marker: `AS02_SFP1_NETWORK_TEST_PASS`. The test verifies 25G link state, ARP MAC `02:00:00:00:00:de`, register probe, loopback, stress/rejection behavior, and NIC error counters.

Why the NIC needs an IPv4 address: the operating system must know which
interface should emit ARP and IPv4 packets for `192.168.0.222`. This address is
assigned to the external controller NIC only. It neither configures nor
describes the FPGA's PCIe PF0.

If the link is down, check optics/DAC compatibility, FEC/link policy, lane/cage
selection, and GT reset state before debugging UDP. If the link is up but ARP
fails, capture on the controller NIC and check that requests leave the intended
interface and that SFP1 RX/TX counters change. If ARP passes but commands fail,
compare UDP port, checksum, peer selection, and payload byte order.

## 3. LeechCore/VMM

Build or copy the AS02 `leechcore.dll` beside the x64 host application. Continue using the device string `fpga`; the AS02 build defaults it to RawUDP `192.168.0.222:28474`.

Start with identity and a small read, then progress to repeated reads/writes and sustained traffic. Record host output and packet captures.

See [LeechCore adapter](leechcore-adapter.md) for the builder outputs, deployment
layout, default/explicit device strings, and mock-test boundary.

Progress through the host path in increasing scope:

1. Create the device with plain `fpga` and record the returned identity.
2. Read PCIe configuration and BAR information.
3. Perform a small aligned read and verify the corresponding MRd/CplD exchange.
4. Perform a small write and verify the MWr request.
5. Repeat scatter reads/writes while correlating pcap and PCIe/ILA counters.
6. Only then start the VMM workload and sustained-throughput test.

This ordering distinguishes transport creation, control commands, BAR/config
state, outbound DMA/TLP operation, and application behavior.

## 4. Evidence

```powershell
.\collect_as02_evidence.ps1 -InterfaceAlias '<25G NIC>' -CaptureSeconds 60
```

For debug images, also supply matching `.bit`, `.ltx`, ILA CSV, and stimulus logs. A complete acceptance set includes PCIe enumeration, SFP1 pcapng, NIC before/after counters, source commit, image hashes, and host commands.

Evidence should state literal commands, exit codes, timestamps, tool versions,
and observed values. Simulation PASS, a programmed JTAG chain, a lit optical
module, and a successful VMM session are different claims and must remain
separate. The release-wide claim rules are listed in
[Validation status](validation.md).
