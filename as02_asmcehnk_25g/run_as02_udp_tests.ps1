param(
    [string]$VivadoBin = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkRoot = Join-Path $ProjectRoot ".tmp_udp_tests"
$SourceRoot = Join-Path $ProjectRoot "src"
$ThirdPartyRoot = Join-Path $ProjectRoot "..\third_party"
$TaxiAxis = Join-Path $ThirdPartyRoot "taxi\src\axis\rtl\taxi_axis_if.sv"
$TaxiAxisAsyncFifo = Join-Path $ThirdPartyRoot "taxi\src\axis\rtl\taxi_axis_async_fifo.sv"
$TaxiSyncReset = Join-Path $ThirdPartyRoot "taxi\src\sync\rtl\taxi_sync_reset.sv"
$TaxiSyncSignal = Join-Path $ThirdPartyRoot "taxi\src\sync\rtl\taxi_sync_signal.sv"
$CorundumEth = Join-Path $ThirdPartyRoot "corundum\fpga\lib\eth\rtl"
$CorundumAxis = Join-Path $ThirdPartyRoot "corundum\fpga\lib\eth\lib\axis\rtl"

if ([string]::IsNullOrWhiteSpace($VivadoBin)) {
    $XvlogCommand = Get-Command xvlog.bat -ErrorAction SilentlyContinue
    if ($null -eq $XvlogCommand) {
        throw "xvlog.bat was not found. Run from a Vivado command shell or pass -VivadoBin."
    }
    $VivadoBin = Split-Path -Parent $XvlogCommand.Source
}

$Xvlog = Join-Path $VivadoBin "xvlog.bat"
$Xelab = Join-Path $VivadoBin "xelab.bat"
$Xsim = Join-Path $VivadoBin "xsim.bat"
foreach ($Tool in @($Xvlog, $Xelab, $Xsim)) {
    if (-not (Test-Path -LiteralPath $Tool)) {
        throw "Required Vivado simulator tool is missing: $Tool"
    }
}

$Sources = @(
    $TaxiAxis
    $TaxiSyncReset
    $TaxiSyncSignal
    $TaxiAxisAsyncFifo
    (Join-Path $SourceRoot "asmcehnk_udp_tx_packetizer_256.v")
    (Join-Path $SourceRoot "asmcehnk_eth_axis_udp_25g.sv")
    (Join-Path $SourceRoot "asmcehnk_com_axis_udp_25g.sv")
    (Join-Path $SourceRoot "asmcehnk_mux.sv")
    (Join-Path $SourceRoot "asmcehnk_fifo.sv")
    (Join-Path $CorundumEth "eth_axis_rx.v")
    (Join-Path $CorundumEth "eth_axis_tx.v")
    (Join-Path $CorundumEth "udp_complete_64.v")
    (Join-Path $CorundumEth "udp_checksum_gen_64.v")
    (Join-Path $CorundumEth "udp_64.v")
    (Join-Path $CorundumEth "udp_ip_rx_64.v")
    (Join-Path $CorundumEth "udp_ip_tx_64.v")
    (Join-Path $CorundumEth "ip_complete_64.v")
    (Join-Path $CorundumEth "ip_64.v")
    (Join-Path $CorundumEth "ip_eth_rx_64.v")
    (Join-Path $CorundumEth "ip_eth_tx_64.v")
    (Join-Path $CorundumEth "ip_arb_mux.v")
    (Join-Path $CorundumEth "arp.v")
    (Join-Path $CorundumEth "arp_cache.v")
    (Join-Path $CorundumEth "arp_eth_rx.v")
    (Join-Path $CorundumEth "arp_eth_tx.v")
    (Join-Path $CorundumEth "eth_arb_mux.v")
    (Join-Path $CorundumEth "lfsr.v")
    (Join-Path $CorundumAxis "arbiter.v")
    (Join-Path $CorundumAxis "priority_encoder.v")
    (Join-Path $CorundumAxis "axis_adapter.v")
    (Join-Path $CorundumAxis "axis_fifo.v")
    (Join-Path $CorundumAxis "axis_fifo_adapter.v")
    (Join-Path $ProjectRoot "tests\tb_udp_rx.sv")
    (Join-Path $ProjectRoot "tests\tb_udp_arp_tx.sv")
    (Join-Path $ProjectRoot "tests\tb_udp_packetizer.sv")
    (Join-Path $ProjectRoot "tests\tb_udp_fifo_e2e.sv")
    (Join-Path $ProjectRoot "tests\tb_udp_sfp1_cdc_e2e.sv")
)
foreach ($Source in $Sources) {
    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Required UDP simulation source is missing: $Source"
    }
}

New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
Push-Location $WorkRoot
try {
    & $Xvlog -sv -d AS02_DISABLE_STARTUPE2 -i $SourceRoot $Sources
    if ($LASTEXITCODE -ne 0) {
        throw "xvlog failed with exit code $LASTEXITCODE"
    }

    $TestCases = [ordered]@{
        "tb_udp_rx" = "UDP_RX_TEST_PASS"
        "tb_udp_arp_tx" = "UDP_ARP_TX_TEST_PASS"
        "tb_udp_packetizer" = "UDP_PACKETIZER_TEST_PASS"
        "tb_udp_fifo_e2e" = "UDP_FIFO_E2E_TEST_PASS"
        "tb_udp_sfp1_cdc_e2e" = "UDP_SFP1_CDC_E2E_TEST_PASS"
    }
    foreach ($Top in $TestCases.Keys) {
        $Snapshot = "${Top}_sim"
        $PassMarker = $TestCases[$Top]
        & $Xelab $Top -s $Snapshot -timescale 1ns/1ps
        if ($LASTEXITCODE -ne 0) {
            throw "xelab failed for $Top with exit code $LASTEXITCODE"
        }
        $SimulationOutput = & $Xsim $Snapshot -runall 2>&1
        $SimulationExitCode = $LASTEXITCODE
        $SimulationOutput | Write-Output
        $SimulationText = $SimulationOutput -join "`n"
        $SimulationLog = Join-Path $WorkRoot "${Top}_xsim.log"
        [System.IO.File]::WriteAllText(
            $SimulationLog,
            $SimulationText + "`n",
            [System.Text.UTF8Encoding]::new($false)
        )
        if ($SimulationExitCode -ne 0 -or $SimulationText -notmatch $PassMarker) {
            throw "xsim failed or did not emit a PASS marker for $Top"
        }
    }
} finally {
    Pop-Location
}

Write-Host "All AS02 UDP focused simulations passed."
