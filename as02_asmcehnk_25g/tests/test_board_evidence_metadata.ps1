param(
    [Parameter(Mandatory = $true)]
    [string]$PowerShellExe
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Collector = Join-Path $ProjectRoot "collect_as02_evidence.ps1"

$DefaultJson = & $PowerShellExe -NoProfile -NonInteractive -File $Collector `
    -InterfaceAlias "TEST-NIC" -MetadataOnly
if ($LASTEXITCODE -ne 0) { throw "Default metadata command failed." }
$Default = $DefaultJson | ConvertFrom-Json
if ($Default.schema_version -ne 1 -or $Default.interface_alias -ne "TEST-NIC") {
    throw "Schema-v1 compatibility fields are missing."
}
if ($Default.transport.controller_nic_interface_alias -ne "TEST-NIC" -or
    -not $Default.pcie_endpoint.independent_of_transport_nic -or
    $Default.pcie_endpoint.expected_vendor_id -ne "10EE" -or
    $Default.pcie_endpoint.expected_device_id -ne "0666" -or
    $Default.pcie_endpoint.expected_class_code -ne "0C0340") {
    throw "Tracked profile metadata was not derived correctly."
}

$OverrideJson = & $PowerShellExe -NoProfile -NonInteractive -File $Collector `
    -InterfaceAlias "TEST-NIC" -MetadataOnly `
    -ExpectedPcieVendorId "1234" -ExpectedPcieDeviceId "abcd" `
    -ExpectedPcieClassCode "0c0340"
if ($LASTEXITCODE -ne 0) { throw "Override metadata command failed." }
$Override = $OverrideJson | ConvertFrom-Json
if ($Override.pcie_endpoint.pnp_pattern -ne "VEN_1234&DEV_ABCD" -or
    $Override.pcie_endpoint.expected_class_code -ne "0C0340") {
    throw "Explicit identity overrides were not normalized."
}

$InvalidOutput = Join-Path $env:TEMP "as02_invalid_identity_$PID.txt"
$InvalidArguments = @(
    "-NoProfile", "-NonInteractive", "-File", $Collector,
    "-InterfaceAlias", "TEST-NIC", "-MetadataOnly",
    "-ExpectedPcieVendorId", "XYZ"
)
$InvalidProcess = Start-Process -FilePath $PowerShellExe `
    -ArgumentList $InvalidArguments -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput $InvalidOutput -RedirectStandardError "$InvalidOutput.err"
$InvalidExitCode = $InvalidProcess.ExitCode
Remove-Item -LiteralPath $InvalidOutput -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$InvalidOutput.err" -Force -ErrorAction SilentlyContinue
if ($InvalidExitCode -eq 0) { throw "Invalid hexadecimal identity was accepted." }

$CompatibleIds = @("PCI\VEN_1234&DEV_ABCD", "PCI\CC_0C0340", "PCI\CC_0C03")
$ActualClass = $null
foreach ($CompatibleId in $CompatibleIds) {
    $Match = [regex]::Match($CompatibleId, '(?i)^PCI\\CC_([0-9A-F]{6})$')
    if ($Match.Success) { $ActualClass = $Match.Groups[1].Value.ToUpperInvariant(); break }
}
if ($ActualClass -ne "0C0340") { throw "PCI CompatibleIds class-code parsing failed." }

Write-Host "AS02_BOARD_EVIDENCE_METADATA_TEST_PASS"
