param(
    [string]$UpstreamRoot = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SourceRoot = Join-Path $ProjectRoot "src"
$IpRoot = Join-Path $ProjectRoot "ip"
$ProfilePath = Join-Path $IpRoot "pcie4_uscale_plus_0_profile.tcl"
$XciPath = Join-Path $IpRoot "pcie4_uscale_plus_0.xci"
$GeneratorPath = Join-Path $ProjectRoot "vivado_generate_project_as02.tcl"
$CorePath = Join-Path $SourceRoot "asmcehnk_as02_core.sv"
$TlpPath = Join-Path $SourceRoot "asmcehnk_pcie_tlp_us.sv"
$FilterPath = Join-Path $SourceRoot "asmcehnk_tlps128_filter.sv"
$UdpPath = Join-Path $SourceRoot "asmcehnk_com_axis_udp_25g.sv"
$PatchPath = Join-Path $ProjectRoot "host\leechcore\as02_default_udp.patch"
$LeechCorePath = Join-Path $ProjectRoot "..\LeechCore\leechcore\device_fpga.c"
$ReuseManifestPath = Join-Path $ProjectRoot "reuse_manifest.json"

foreach ($Path in @($ProfilePath, $XciPath, $GeneratorPath, $CorePath, $TlpPath, $FilterPath, $UdpPath, $PatchPath, $LeechCorePath, $ReuseManifestPath)) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Required audit input is missing: $Path" }
}

$Profile = Get-Content -LiteralPath $ProfilePath -Raw
$Xci = Get-Content -LiteralPath $XciPath -Raw
$Generator = Get-Content -LiteralPath $GeneratorPath -Raw
$Core = Get-Content -LiteralPath $CorePath -Raw
$Tlp = Get-Content -LiteralPath $TlpPath -Raw
$Filter = Get-Content -LiteralPath $FilterPath -Raw
$Udp = Get-Content -LiteralPath $UdpPath -Raw
$Patch = Get-Content -LiteralPath $PatchPath -Raw
$LeechCore = Get-Content -LiteralPath $LeechCorePath -Raw

# The proven PCILeech VID/DID/BAR envelope remains in place, while PF0 uses the
# active AMDUSB4 non-network class. Transport remains outside the PCIe function.
$ExpectedProfile = [ordered]@{
    CFG_VEND_ID = "10EE"
    CFG_DEV_ID = "0666"
    CLASS_CODE = "0C0340"
    BAR0_64BIT = "false"
    BAR0_SIZE = "4"
    MSI_CAP_ON = "true"
    MSIX_CAP_ON = "false"
}
foreach ($Name in $ExpectedProfile.Keys) {
    $Match = [regex]::Match($Profile, "(?m)^\s*variable\s+$Name\s+\{([^}]*)\}\s*$")
    if (-not $Match.Success -or $Match.Groups[1].Value.Trim().ToLowerInvariant() -ne $ExpectedProfile[$Name].ToLowerInvariant()) {
        throw "Profile baseline mismatch for $Name"
    }
}
foreach ($Needle in @('"PF0_DEVICE_ID": [ { "value": "0666"', '"PF0_CLASS_CODE": [ { "value": "0C0340"', '"PF0_Use_Class_Code_Lookup_Assistant": [ { "value": "false"', '"pf0_class_code_base": [ { "value": "0C"', '"pf0_class_code_sub": [ { "value": "03"', '"pf0_class_code_interface": [ { "value": "40"', '"pf0_bar0_64bit": [ { "value": "false"', '"pf0_bar0_size": [ { "value": "4"', '"pf0_msi_enabled": [ { "value": "true"', '"pf0_msix_enabled": [ { "value": "false"')) {
    if ($Xci.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "XCI baseline field is missing: $Needle" }
}
if ($Xci -match '(?i)(cfg_ext_false_test|\.tmp_|tmp_[A-Za-z0-9])') {
    throw "Checked-in PCIe XCI contains a temporary experiment path."
}
if ($Xci.IndexOf('"gen_directory": "../../../../fpga.gen/sources_1/ip/pcie4_uscale_plus_0"', [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -or
    $Xci.IndexOf('"OUTPUTDIR": [ { "value": "../../../../fpga.gen/sources_1/ip/pcie4_uscale_plus_0"', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
    throw "Checked-in PCIe XCI generation directory is not the AS02 fpga project path."
}

# The active AS02 path has one UDP transport port and keeps the second SFP data path idle.
foreach ($Needle in @("AS02_TRANSPORT_SFP_INDEX = 32'd0", "AS02_IDLE_SFP_INDEX      = 32'd1", "mac_axis_tx[AS02_IDLE_SFP_INDEX].tvalid = 1'b0", "mac_axis_rx[AS02_IDLE_SFP_INDEX].tready = 1'b1")) {
    if ($Core.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "SFP1/SFP2 policy is missing: $Needle" }
}
foreach ($Needle in @('net_reset_to_pcie_sync_inst', 'reg_pcie_path_rst_pcie <= pcie_rst | net_rst_pcie', 'assign pcie_path_rst_pcie = reg_pcie_path_rst_pcie', '.rst_pcie                                (pcie_path_rst_pcie)', '.rst                  (pcie_path_rst_pcie)')) {
    if ($Core.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "Bidirectional PCIe/network reset contract is missing: $Needle" }
}

# The generator must select the AS02 PCIe4 XCI and SFP/UDP sources, not A7 or FT601 roots.
if ($Generator.IndexOf('pcie4_uscale_plus_0.xci', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "AS02 generator does not import PCIe4 XCI" }
if ($Generator.IndexOf('asmcehnk_com_axis_udp_25g.sv', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "AS02 generator does not include UDP adapter" }
if ($Generator.IndexOf('asmcehnk_tlps128_filter.sv', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "AS02 generator does not include reusable TLP filter" }
foreach ($Forbidden in @('pcie_7x_0.xci', 'pcie_7x_0_core_top.v', 'asmcehnk_pcie_tlp_a7.sv', 'asmcehnk_ft601.sv', 'FC1003_RMII')) {
    $ActiveGeneratorText = $Generator
    $XciBlock = [regex]::Match($Generator, '(?s)set\s+xci_files\s+\[list(.*?)\]\s*\n')
    if ($XciBlock.Success) { $ActiveGeneratorText = $XciBlock.Groups[1].Value }
    if ($ActiveGeneratorText.IndexOf($Forbidden, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { throw "Legacy source is active in generator: $Forbidden" }
}

# The LeechCore host contract changes only the default physical transport selection.
foreach ($Needle in @('AS02_DEFAULT_RAWUDP', 'AS02_DEFAULT_RAWUDP_IP', 'DeviceFPGA_InitializeUDP', 'fpga')) {
    if ($Patch.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "LeechCore default-UDP patch field is missing: $Needle" }
}
if ($LeechCore.IndexOf('DeviceFPGA_InitializeUDP(ctx, 28474', [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -and
    $LeechCore.IndexOf('DeviceFPGA_InitializeUDP(ctx, dwIpAddr)', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
    throw "LeechCore UDP initializer is missing"
}
if ($LeechCore.IndexOf('28474', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "LeechCore UDP port 28474 is missing" }

# The adapter is the only 256-bit boundary; the reusable framework remains raw 128-bit.
foreach ($Needle in @('IfAXIS128', 'asmcehnk_pcie_us_cq_to_tlps128', 'asmcehnk_tlps128_to_axis_cc_us', 'asmcehnk_tlps128_to_axis_rq_us', 'asmcehnk_pcie_us_rc_to_tlps128')) {
    if ($Tlp.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "PCIe 128/256 adapter contract is missing: $Needle" }
}
foreach ($Needle in @('module asmcehnk_tlps128_filter', 'is_tlphdr_cpl', 'is_tlphdr_cfg', 'filter_next')) {
    if ($Filter.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "Reusable TLP filter contract is missing: $Needle" }
}
foreach ($Needle in @('IfComToFifo', '64-bit RX', '256-bit TX')) {
    if ($Udp.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "UDP/IfComToFifo contract is missing: $Needle" }
}

# Reusable framework files must remain byte-identical to the published migration baseline.
$ReuseManifest = Get-Content -LiteralPath $ReuseManifestPath -Raw | ConvertFrom-Json
if ($ReuseManifest.schema -ne 'as02-framework-reuse-v1') { throw "Unsupported reuse manifest schema" }
$Sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    foreach ($Item in $ReuseManifest.files) {
        $RelativePath = [string]$Item.path
        $SourcePath = Join-Path $ProjectRoot ($RelativePath -replace '/', '\')
        if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
            throw "AS02 reusable source is absent: $RelativePath"
        }
        $ActualHash = [System.BitConverter]::ToString(
            $Sha256.ComputeHash([System.IO.File]::ReadAllBytes($SourcePath))
        ).Replace('-', '')
        if ($ActualHash -ne ([string]$Item.sha256).ToUpperInvariant()) {
            throw "Reusable source drifted from published baseline: $RelativePath"
        }
    }
} finally {
    $Sha256.Dispose()
}

Write-Host "AS02_TRANSPORT_IDENTITY_REUSE_AUDIT_PASS"
Write-Host "PF0 baseline: 10EE:0666 class 0C0340; transport: controller 25G NIC -> SFP1 -> RawUDP"
Write-Host "SFP2 policy: no transport frames; AXIS TX idle / RX drain"
Write-Host "Raw TLP contract: 128-bit internal; 256-bit only at PCIe4 adapter"
Write-Host "Reset contract: network and PCIe resets flush both sides of the PCIe soft-path CDC FIFOs"
