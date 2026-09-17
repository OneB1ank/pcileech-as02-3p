param(
    [string]$VivadoBin = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkRoot = Join-Path $ProjectRoot ".tmp_pcie_profile"
$TestScript = Join-Path $ProjectRoot "tests\verify_pcie_profile.tcl"

if ([string]::IsNullOrWhiteSpace($VivadoBin)) {
    $VivadoCommand = Get-Command vivado.bat -ErrorAction SilentlyContinue
    if ($null -eq $VivadoCommand) {
        throw "vivado.bat was not found. Run from a Vivado command shell or pass -VivadoBin."
    }
    $VivadoBin = Split-Path -Parent $VivadoCommand.Source
}

$Vivado = Join-Path $VivadoBin "vivado.bat"
if (-not (Test-Path -LiteralPath $Vivado)) {
    throw "Vivado batch entry is missing: $Vivado"
}

$env:AS02_PCIE_PROFILE_WORK_DIR = $WorkRoot
$Output = & $Vivado -mode batch -nojournal -nolog -notrace -source $TestScript 2>&1
$ExitCode = $LASTEXITCODE
$Output | Write-Output
$Text = $Output -join "`n"

New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
$Transcript = Join-Path $WorkRoot "pcie_profile_test.log"
[System.IO.File]::WriteAllText(
    $Transcript,
    $Text + "`n",
    [System.Text.UTF8Encoding]::new($false)
)

if ($ExitCode -ne 0 -or $Text -notmatch "AS02_PCIE_PROFILE_TEST_PASS") {
    throw "AS02 PCIe profile regression failed with exit code $ExitCode"
}

Write-Host "AS02 PCIe profile/XCI regression passed."
