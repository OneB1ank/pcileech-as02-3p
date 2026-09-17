param(
    [string]$VivadoBin = "",
    [switch]$IntegrationOnly
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$WorkRoot = Join-Path $ProjectRoot ".tmp_pcie_tests\$RunStamp"
$XciWorkRoot = Join-Path $WorkRoot "xci_fifo_pair"
$IntegrationWorkRoot = Join-Path $WorkRoot "tlp_us_integration"
$SourceRoot = Join-Path $ProjectRoot "src"
$TestsRoot = Join-Path $ProjectRoot "tests"
$TaxiAxis = Join-Path $ProjectRoot "..\third_party\taxi\src\axis\rtl\taxi_axis_if.sv"
$Adapter = Join-Path $SourceRoot "asmcehnk_pcie_tlp_us.sv"
$CfgBridge = Join-Path $SourceRoot "asmcehnk_pcie_cfg_us.sv"
$DstFifo = Join-Path $SourceRoot "asmcehnk_tlps128_dst_fifo_us.sv"
$SrcFifo = Join-Path $SourceRoot "asmcehnk_tlps128_src_fifo.sv"
$SrcElastic = Join-Path $SourceRoot "asmcehnk_tlps128_src_elastic_us.sv"
$FlowControlTestbench = Join-Path $ProjectRoot "tests\tb_pcie_flow_control.sv"
$CqAtomicTestbench = Join-Path $ProjectRoot "tests\tb_pcie_cq_atomic_ur.sv"
$LeechCoreTestbench = Join-Path $ProjectRoot "tests\tb_pcie_leechcore_128_256.sv"
$CfgTestbench = Join-Path $ProjectRoot "tests\tb_pcie_drp_bar_info.sv"
$DstFifoTestbench = Join-Path $ProjectRoot "tests\tb_pcie_dst_fifo_us.sv"
$SrcFifoTestbench = Join-Path $ProjectRoot "tests\tb_pcie_src_fifo_rq_us.sv"
$IntegrationTestbench = Join-Path $ProjectRoot "tests\tb_pcie_tlp_us_integration.sv"
$GeneratedIpRoot = Join-Path $ProjectRoot "fpga.gen\sources_1\ip"
$TokenFifoNetlist = Join-Path $GeneratedIpRoot `
    "fifo_1_1_clk2\fifo_1_1_clk2_sim_netlist.v"
$DataFifoNetlist = Join-Path $GeneratedIpRoot `
    "fifo_134_134_clk2_rxfifo\fifo_134_134_clk2_rxfifo_sim_netlist.v"
$IntegrationNetlists = @(
    "bram_bar_zero4k\bram_bar_zero4k_sim_netlist.v",
    "bram_pcie_cfgspace\bram_pcie_cfgspace_sim_netlist.v",
    "drom_pcie_cfgspace_writemask\drom_pcie_cfgspace_writemask_sim_netlist.v",
    "fifo_129_129_clk1\fifo_129_129_clk1_sim_netlist.v",
    "fifo_134_134_clk1_bar_rdrsp\fifo_134_134_clk1_bar_rdrsp_sim_netlist.v",
    "fifo_134_134_clk2\fifo_134_134_clk2_sim_netlist.v",
    "fifo_134_134_clk2_rxfifo\fifo_134_134_clk2_rxfifo_sim_netlist.v",
    "fifo_141_141_clk1_bar_wr\fifo_141_141_clk1_bar_wr_sim_netlist.v",
    "fifo_1_1_clk2\fifo_1_1_clk2_sim_netlist.v",
    "fifo_43_43_clk2\fifo_43_43_clk2_sim_netlist.v",
    "fifo_49_49_clk2\fifo_49_49_clk2_sim_netlist.v",
    "fifo_74_74_clk1_bar_rd1\fifo_74_74_clk1_bar_rd1_sim_netlist.v"
) | ForEach-Object { Join-Path $GeneratedIpRoot $_ }

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

New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
if (-not $IntegrationOnly) {
Push-Location $WorkRoot
try {
    & $Xvlog -sv -i $SourceRoot $TaxiAxis $Adapter $CfgBridge $DstFifo `
        $SrcFifo $SrcElastic `
        $FlowControlTestbench $CqAtomicTestbench $LeechCoreTestbench `
        $CfgTestbench $DstFifoTestbench $SrcFifoTestbench
    if ($LASTEXITCODE -ne 0) {
        throw "xvlog failed with exit code $LASTEXITCODE"
    }

    $TestCases = [ordered]@{
        "tb_pcie_mux_backpressure" = "PCIE_MUX_BACKPRESSURE_TEST_PASS"
        "tb_pcie_cc_native_arbiter" = "PCIE_CC_NATIVE_ARBITER_TEST_PASS"
        "tb_pcie_cq_rc_merge" = "PCIE_CQ_RC_MERGE_TEST_PASS"
        "tb_pcie_rq_credit" = "PCIE_RQ_CREDIT_TEST_PASS"
        "tb_pcie_cc_multibeat" = "PCIE_CC_MULTIBEAT_TEST_PASS"
        "tb_pcie_tag_lifecycle" = "PCIE_TAG_LIFECYCLE_TEST_PASS"
        "tb_pcie_cq_atomic_malformed" = "PCIE_CQ_ATOMIC_MALFORMED_TEST_PASS"
        "tb_pcie_cq_unsupported_ur" = "PCIE_CQ_UNSUPPORTED_UR_TEST_PASS"
        "tb_pcie_leechcore_128_256" = "PCIE_LEECHCORE_128_256_TEST_PASS"
        "tb_pcie_drp_bar_info" = "PCIE_DRP_BAR_INFO_TEST_PASS"
        "tb_pcie_dst_fifo_us" = "PCIE_DST_FIFO_US_TEST_PASS"
        "tb_pcie_src_fifo_rq_us" = "PCIE_SRC_FIFO_RQ_ELASTIC_TEST_PASS"
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

foreach ($Netlist in @($TokenFifoNetlist, $DataFifoNetlist)) {
    if (-not (Test-Path -LiteralPath $Netlist)) {
        throw "Generated FIFO simulation model is missing: $Netlist. Run the AS02 Vivado build (or generate the project and synthesize the reusable IP) before the generated-XCI integration test."
    }
}

# Repeat the source-FIFO/RQ test with both generated independent-clock XCI
# models.  Mixing one behavioral FIFO with one XCI can create artificial CDC
# latency skew, so the token and data FIFOs are always validated as a pair.
New-Item -ItemType Directory -Path $XciWorkRoot -Force | Out-Null
Push-Location $XciWorkRoot
try {
    & $Xvlog -sv -d AS02_USE_XCI_FIFO_MODEL -i $SourceRoot `
        $TokenFifoNetlist $DataFifoNetlist $TaxiAxis $Adapter `
        $SrcFifo $SrcElastic $SrcFifoTestbench
    if ($LASTEXITCODE -ne 0) {
        throw "xvlog failed for generated FIFO XCI models with exit code $LASTEXITCODE"
    }

    $Snapshot = "tb_pcie_src_fifo_rq_xci_sim"
    & $Xelab tb_pcie_src_fifo_rq_us glbl -s $Snapshot `
        -timescale 1ns/1ps -L unisims_ver -L xpm
    if ($LASTEXITCODE -ne 0) {
        throw "xelab failed for generated FIFO XCI models with exit code $LASTEXITCODE"
    }

    $SimulationOutput = & $Xsim $Snapshot -runall 2>&1
    $SimulationExitCode = $LASTEXITCODE
    $SimulationOutput | Write-Output
    $SimulationText = $SimulationOutput -join "`n"
    $SimulationLog = Join-Path $XciWorkRoot "tb_pcie_src_fifo_rq_xci_xsim.log"
    [System.IO.File]::WriteAllText(
        $SimulationLog,
        $SimulationText + "`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    if ($SimulationExitCode -ne 0 -or
        $SimulationText -notmatch "PCIE_SRC_FIFO_RQ_ELASTIC_TEST_PASS") {
        throw "Generated FIFO XCI pair simulation failed or did not emit its PASS marker"
    }
} finally {
    Pop-Location
}
}

foreach ($Netlist in $IntegrationNetlists) {
    if (-not (Test-Path -LiteralPath $Netlist)) {
        throw "Generated PCIe integration simulation model is missing: $Netlist"
    }
}

$IntegrationMifFiles = @(
    (Join-Path $GeneratedIpRoot "bram_bar_zero4k\bram_bar_zero4k.mif")
    (Join-Path $GeneratedIpRoot "bram_pcie_cfgspace\bram_pcie_cfgspace.mif")
    (Join-Path $GeneratedIpRoot "drom_pcie_cfgspace_writemask\drom_pcie_cfgspace_writemask.mif")
)
$TaxiSync = Join-Path $ProjectRoot `
    "..\third_party\taxi\src\sync\rtl\taxi_sync_signal.sv"
$Filter = Join-Path $SourceRoot "asmcehnk_tlps128_filter.sv"
$SinkMux = Join-Path $SourceRoot "asmcehnk_tlps128_sink_mux1.sv"
$CfgShadow = Join-Path $SourceRoot "asmcehnk_tlps128_cfgspace_shadow.sv"
$BarController = Join-Path $SourceRoot "asmcehnk_tlps128_bar_controller.sv"
$XsimBs16Compat = Join-Path $TestsRoot "xsim_bs16_compat.sv"

New-Item -ItemType Directory -Path $IntegrationWorkRoot -Force | Out-Null
if (-not (Test-Path -LiteralPath $XsimBs16Compat)) {
    throw "XSim legacy macro compatibility shim is missing: $XsimBs16Compat"
}
foreach ($MifFile in $IntegrationMifFiles) {
    if (-not (Test-Path -LiteralPath $MifFile)) {
        throw "Generated PCIe integration memory image is missing: $MifFile"
    }
    Copy-Item -LiteralPath $MifFile -Destination $IntegrationWorkRoot -Force
}

Push-Location $IntegrationWorkRoot
try {
    & $Xvlog -sv -i $SourceRoot $IntegrationNetlists $TaxiAxis $TaxiSync `
        $Adapter $DstFifo $SrcFifo $SrcElastic $Filter $SinkMux `
        $XsimBs16Compat $CfgShadow $BarController $IntegrationTestbench
    if ($LASTEXITCODE -ne 0) {
        throw "xvlog failed for the complete PCIe TLP integration test with exit code $LASTEXITCODE"
    }

    $Snapshot = "tb_pcie_tlp_us_integration_sim"
    & $Xelab tb_pcie_tlp_us_integration glbl -s $Snapshot `
        -timescale 1ns/1ps -L unisims_ver -L xpm
    if ($LASTEXITCODE -ne 0) {
        throw "xelab failed for the complete PCIe TLP integration test with exit code $LASTEXITCODE"
    }

    $SimulationOutput = & $Xsim $Snapshot -runall 2>&1
    $SimulationExitCode = $LASTEXITCODE
    $SimulationOutput | Write-Output
    $SimulationText = $SimulationOutput -join "`n"
    $SimulationLog = Join-Path $IntegrationWorkRoot `
        "tb_pcie_tlp_us_integration_xsim.log"
    [System.IO.File]::WriteAllText(
        $SimulationLog,
        $SimulationText + "`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    if ($SimulationExitCode -ne 0 -or
        $SimulationText -notmatch "PCIE_TLP_US_INTEGRATION_TEST_PASS") {
        throw "Complete PCIe TLP integration simulation failed or did not emit its PASS marker"
    }
} finally {
    Pop-Location
}

Write-Host "All AS02 PCIe simulations passed, including generated XCI/BRAM integration."
Write-Host "AS02_PCIE_TEST_RUN_DIR=$WorkRoot"
