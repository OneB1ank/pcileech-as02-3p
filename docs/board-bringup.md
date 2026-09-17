# Board bring-up

Use the gates in order and retain evidence from each gate. A later gate does not
imply that an earlier gate passed. The order isolates FPGA/JTAG configuration,
persistent boot, PCIe, the independent SFP1 RawUDP transport, and the LeechCore
memory/TLP API.

## Current hardware state

As of **September 17, 2026**, the local Vivado Hardware Manager sees the
programmer/target but does not list `xcku3p_0`. Bring-up is therefore stopped at
Gate 1. No programming operation can run in this current state.

The confirmed board configuration memory is one Micron MT25QU256, 256 Mbit,
single-device QSPI x4.

Historical external-baseline evidence from **August 26, 2026** is retained
separately: `xcku3p_0` was visible, `mt25qu256-spi-x1_x2_x4` was selected, and
Erase plus Program/Verify completed for the external Corundum image. A later
JTAG refresh after `boot_hw_device` reported `DONE_PIN=1` and `ISC_DONE=1`.

The historical PRM reports `Size 256M` and end address `0x0FFFFFFF`, because it
was created with the old `-size 256` argument that Vivado interprets as 256
MBytes. It demonstrates that the JTAG/cfgmem path operated in that session, but
it is not the correct 32 MiB MT25QU256 mapping, not a project normal image, and
not current release or physical power-cycle acceptance evidence.

## Gate 0: Prepare the bench

- Record the project source commit and SHA-256 of every image used.
- Confirm the board has stable power and the programmer sees the expected VREF.
- Recheck TCK, TMS, TDI, TDO, GND, and VREF against the board/programmer pinout.
- Verify that the controller cable is connected to physical **SFP1**, not SFP2.
- Keep the target PCIe connection separate from the controller NIC/IPv4 path.
- Use a matching `.ltx` only with the debug `.bit` from the same build.

See [Architecture](architecture.md) for the independent transport and PCIe
planes and [Vivado programming](vivado-programming.md) for detailed programming
instructions.

## Gate 1: Detect the FPGA in the JTAG chain

Open **Hardware Manager → Open Target → Auto Connect**. Required evidence:

- the hardware target/programmer is visible;
- `xcku3p_0` appears in the device tree or `get_hw_devices` output.

If only the programmer appears or Vivado reports **No devices detected**, stop
image testing and investigate board power, VREF, ground, TDI/TDO direction,
wire order, cable connection, TCK rate, and `hw_server` state.

The MT25QU256 is reached indirectly through the FPGA. The configuration memory
cannot be attached or programmed while `xcku3p_0` is absent.

## Gate 2: Temporarily program a BIT image

After Gate 1 passes, right-click `xcku3p_0`, choose **Program Device**, and use
this order:

1. Load the external known-good board baseline `corundum_k3pq_25g.bit` and
   reproduce/record its behavior if current board diagnosis requires it.
2. Load this project's normal `fpga.bit` and record its behavior.
3. Use `fpga_debug.bit` plus its matching `fpga_debug.ltx` only when ILA/VIO
   observation is needed.

The external baseline is a local diagnostic input, not a repository release
asset. Its recorded SHA-256 is:

```text
0E57638430E2DDF41A415D1F8A60465D475F26974D946245D5814E0C45768A8C
```

The August 26 external diagnostic does not replace this gate for the current
bench state or project image. JTAG BIT programming is volatile and disappears
after power-off. Successful Program Device proves FPGA configuration only; it
does not prove persistent boot, PCIe, SFP1, BAR/DMA, or LeechCore.

## Gate 3: Program the MT25QU256

Only after the intended normal BIT works temporarily:

1. Generate a 32 MiB (256 Mbit), SPIx4 MCS from the normal BIT at address
   `0x00000000`; Vivado 2024.2 uses `write_cfgmem -size 32` because the option is
   expressed in MBytes.
2. Right-click the FPGA and choose **Add Configuration Memory Device**.
3. Search `mt25qu256` and prefer `mt25qu256-spi-x1_x2_x4`; the explicit
   single-x4 alternative is `mt25qu256-qspi-x4-single`.
4. Reject dual-stacked, dual-parallel/x8, BPI, and wrong-capacity entries.
5. Program the MCS with **Erase**, **Program**, and **Verify** enabled.
6. Save the selected part, operation log, source BIT hash, and MCS/PRM hashes.

Then remove and restore board power with the boot mode set for Master SPI/QSPI.
Automatic configuration after power-cycle is a separate required result; Flash
Verify alone is insufficient.

## Gate 4: Enumerate PCIe

For reliable cold enumeration, ensure the FPGA is configured before or during
the target-host reset. A Device Manager refresh alone may not retrain and
re-enumerate the endpoint.

Confirm:

- VID/DID and class;
- BDF;
- BAR0 address and 4 KiB size;
- negotiated link width and speed;
- configuration capabilities.

The tracked profile is `10EE:0666`, class `0C0340`, 4 KiB 32-bit BAR0, MSI
enabled, and MSI-X disabled.

This gate comes before PCIe transaction tests because CQ/CC and RQ/RC require a
trained link and Root Complex-assigned resources. Network traffic cannot prove
PCIe enumeration.

## Gate 5: Connect and test SFP1

Connect a 25G controller NIC to physical SFP1 with compatible SFP28 modules and
LC-LC fiber. SFP2 is not a transport port.

Assign the controller NIC an unused address in the FPGA endpoint subnet, for
example `192.168.0.10/24`. This belongs only to the external controller NIC.

```powershell
New-NetIPAddress -InterfaceAlias '<25G NIC>' -IPAddress 192.168.0.10 -PrefixLength 24
cd .\as02_asmcehnk_25g
.\test_as02_sfp1.ps1 -InterfaceAlias '<25G NIC>' -StressIterations 1000
```

Expected marker: `AS02_SFP1_NETWORK_TEST_PASS`. The script checks 25G link
state, ARP MAC `02:00:00:00:00:de`, command/register probing, loopback,
stress/rejection behavior, and NIC error counters.

The NIC needs IPv4 so the operating system knows which interface should emit
ARP/IPv4 packets for `192.168.0.222`. This address neither configures nor
describes the FPGA's PCIe PF0.

If link is down, check optics/DAC compatibility, FEC/link policy, cage/lane
selection, and GT reset state. If link is up but ARP fails, capture on the
controller NIC and correlate RX/TX counters. If ARP passes but commands fail,
compare UDP port, checksum, peer-header selection, and payload byte order.

## Gate 6: LeechCore, BAR, and DMA

Build or copy the AS02 `leechcore.dll` beside the x64 host application. Continue
using device string `fpga`; the AS02 build selects RawUDP
`192.168.0.222:28474` by default.

Progress in increasing scope:

1. Create the device and record returned identity.
2. Read PCIe configuration, DRP/config mirror, and BAR information.
3. Perform BAR0 reads/writes through real CQ/CC traffic.
4. Perform a small aligned memory read and verify MRd/CplD on RQ/RC.
5. Perform a small memory write and verify MWr.
6. Repeat scatter reads/writes while correlating packet and PCIe/ILA counters.
7. Start the VMM workload and sustained traffic only after the smaller tests.

See [LeechCore adapter](leechcore-adapter.md) for builder outputs, deployment,
default/explicit device strings, and the mock-test boundary.

## Gate 7: Collect evidence

```powershell
.\collect_as02_evidence.ps1 -InterfaceAlias '<25G NIC>' -CaptureSeconds 60
```

A complete acceptance set contains:

- source commit and tool versions;
- BIT, optional LTX, MCS and PRM hashes;
- JTAG device list and Program Device result;
- MT25QU256 part selection and Erase/Program/Verify log;
- power-cycle boot result;
- PCIe enumeration, BAR and RQ/RC evidence;
- SFP1 pcapng and NIC before/after counters;
- LeechCore/VMM commands, literal output, and exit codes;
- optional ILA CSV and stimulus logs.

Simulation PASS, a visible programmer, a visible FPGA, successful volatile
programming, Flash Verify, power-cycle boot, PCIe enumeration, SFP carrier, and
a LeechCore session are separate claims. See
[Validation status](validation.md) for the release-wide evidence model.
