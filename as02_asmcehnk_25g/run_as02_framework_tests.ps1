param(
    [string]$VivadoBin = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkRoot = Join-Path $ProjectRoot ".tmp_framework_tests"
$SourceRoot = Join-Path $ProjectRoot "src"
$Mux = Join-Path $SourceRoot "asmcehnk_mux.sv"
$Fifo = Join-Path $SourceRoot "asmcehnk_fifo.sv"
$Testbench = Join-Path $ProjectRoot "tests\tb_asmcehnk_fifo_compat.sv"

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
Push-Location $WorkRoot
try {
    & $Xvlog -sv -d AS02_DISABLE_STARTUPE2 -i $SourceRoot `
        $Mux $Fifo $Testbench
    if ($LASTEXITCODE -ne 0) {
        throw "xvlog failed with exit code $LASTEXITCODE"
    }

    $Top = "tb_asmcehnk_fifo_compat"
    $Snapshot = "${Top}_sim"
    $PassMarker = "ASMCEHNK_FIFO_COMPAT_TEST_PASS"
    & $Xelab $Top -s $Snapshot -timescale 1ns/1ps
    if ($LASTEXITCODE -ne 0) {
        throw "xelab failed with exit code $LASTEXITCODE"
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
    if ($SimulationExitCode -ne 0 -or
        $SimulationText -notmatch $PassMarker) {
        throw "xsim failed or did not emit the framework PASS marker"
    }
} finally {
    Pop-Location
}

Write-Host "All AS02 asmcehnk framework simulations passed."
