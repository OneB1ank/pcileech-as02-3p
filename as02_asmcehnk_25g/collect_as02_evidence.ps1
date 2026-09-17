param(
    [Parameter(Mandatory = $true)]
    [string]$InterfaceAlias,

    [ValidateRange(1, 3600)]
    [int]$CaptureSeconds = 20,

    [string]$BitstreamPath = ".\fpga_debug.bit",

    [string]$ProbesPath = ".\fpga_debug.ltx",

    [string[]]$IlaCsvPath = @(),

    [string]$StimulusLogPath = "",

    [string]$DebugMapPath = ".\as02_debug_map.json",

    [string]$PcieProfilePath = ".\ip\pcie4_uscale_plus_0_profile.tcl",

    [string]$ExpectedPcieVendorId = "",

    [string]$ExpectedPcieDeviceId = "",

    [string]$ExpectedPcieClassCode = "",

    [switch]$MetadataOnly
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$EvidenceRoot = Join-Path $ProjectRoot "board_evidence_$Timestamp"
$PcapPath = Join-Path $EvidenceRoot "sfp1_arp_udp.pcapng"
$SummaryPath = Join-Path $EvidenceRoot "summary.txt"
$ManifestPath = Join-Path $EvidenceRoot "manifest.json"

if ([System.IO.Path]::IsPathRooted($PcieProfilePath)) {
    $PcieProfileCandidate = $PcieProfilePath
} else {
    $PcieProfileCandidate = Join-Path $ProjectRoot $PcieProfilePath
}
$PcieProfileResolved = (Resolve-Path -LiteralPath $PcieProfileCandidate -ErrorAction Stop).Path
$PcieProfileText = Get-Content -LiteralPath $PcieProfileResolved -Raw
$PcieProfileHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PcieProfileResolved).Hash.ToLowerInvariant()

if ([string]::IsNullOrWhiteSpace($ExpectedPcieVendorId)) {
    $Match = [regex]::Match($PcieProfileText, '(?m)^\s*variable\s+CFG_VEND_ID\s+\{([0-9A-Fa-f]{4})\}\s*$')
    if (-not $Match.Success) {
        throw "CFG_VEND_ID was not found in PCIe profile: $PcieProfileResolved"
    }
    $ExpectedPcieVendorId = $Match.Groups[1].Value
}
if ([string]::IsNullOrWhiteSpace($ExpectedPcieDeviceId)) {
    $Match = [regex]::Match($PcieProfileText, '(?m)^\s*variable\s+CFG_DEV_ID\s+\{([0-9A-Fa-f]{4})\}\s*$')
    if (-not $Match.Success) {
        throw "CFG_DEV_ID was not found in PCIe profile: $PcieProfileResolved"
    }
    $ExpectedPcieDeviceId = $Match.Groups[1].Value
}
if ([string]::IsNullOrWhiteSpace($ExpectedPcieClassCode)) {
    $Match = [regex]::Match($PcieProfileText, '(?m)^\s*variable\s+CLASS_CODE\s+\{([0-9A-Fa-f]{6})\}\s*$')
    if (-not $Match.Success) {
        throw "CLASS_CODE was not found in PCIe profile: $PcieProfileResolved"
    }
    $ExpectedPcieClassCode = $Match.Groups[1].Value
}

$ExpectedPcieVendorId = $ExpectedPcieVendorId.ToUpperInvariant()
$ExpectedPcieDeviceId = $ExpectedPcieDeviceId.ToUpperInvariant()
$ExpectedPcieClassCode = $ExpectedPcieClassCode.ToUpperInvariant()
if ($ExpectedPcieVendorId -notmatch '^[0-9A-F]{4}$' -or
    $ExpectedPcieDeviceId -notmatch '^[0-9A-F]{4}$' -or
    $ExpectedPcieClassCode -notmatch '^[0-9A-F]{6}$') {
    throw "Expected PCIe identity must be hexadecimal VID(4), DID(4), class(6)."
}
$PciePnpPattern = "VEN_${ExpectedPcieVendorId}&DEV_${ExpectedPcieDeviceId}"
$PciePnpRegex = [regex]::Escape($PciePnpPattern)
$TransportMetadata = [ordered]@{
    physical_port = "SFP1"
    controller_nic_interface_alias = $InterfaceAlias
    ipv4_purpose = "ARP/IPv4/UDP transport only"
    endpoint = "192.168.0.222:28474"
}
$PcieEndpointMetadata = [ordered]@{
    independent_of_transport_nic = $true
    expected_vendor_id = $ExpectedPcieVendorId
    expected_device_id = $ExpectedPcieDeviceId
    expected_class_code = $ExpectedPcieClassCode
    pnp_pattern = $PciePnpPattern
    profile_path = $PcieProfileResolved
    profile_sha256 = $PcieProfileHash
}

if ($MetadataOnly) {
    [ordered]@{
        schema_version = 1
        interface_alias = $InterfaceAlias
        transport = $TransportMetadata
        pcie_endpoint = $PcieEndpointMetadata
    } | ConvertTo-Json -Depth 5
    exit 0
}

New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null

"AS02MC04 board evidence $Timestamp" | Set-Content -Path $SummaryPath
"SFP1 controller-side physical 25G transport NIC: $InterfaceAlias" | Add-Content -Path $SummaryPath
"FPGA PCIe PF0 expected from profile: ${ExpectedPcieVendorId}:${ExpectedPcieDeviceId}, class $ExpectedPcieClassCode" | Add-Content -Path $SummaryPath
"Transport NIC IPv4 and FPGA PCIe PF0 identity are independent." | Add-Content -Path $SummaryPath
"Capture seconds: $CaptureSeconds" | Add-Content -Path $SummaryPath

$GitCommit = (git -C $ProjectRoot rev-parse HEAD 2>$null | Out-String).Trim()
$GitStatus = (git -C $ProjectRoot status --short 2>$null | Out-String).Trim()
$ArtifactRecords = [System.Collections.Generic.List[object]]::new()

"`r`n===== Git source =====" | Add-Content -Path $SummaryPath
& {
    try {
        git -C $ProjectRoot status --short --branch
        git -C $ProjectRoot rev-parse HEAD
    } catch {
        "ERROR: $($_.Exception.Message)"
    }
} 2>&1 | Out-String | Add-Content -Path $SummaryPath

"`r`n===== Image hashes =====" | Add-Content -Path $SummaryPath
& {
    foreach ($Path in @($BitstreamPath, $ProbesPath, $DebugMapPath)) {
        try {
            if ([System.IO.Path]::IsPathRooted($Path)) {
                $Candidate = $Path
            } else {
                $Candidate = Join-Path $ProjectRoot $Path
            }
            $Resolved = Resolve-Path -Path $Candidate -ErrorAction Stop
            $Hash = Get-FileHash -Algorithm SHA256 -Path $Resolved
            $File = Get-Item -LiteralPath $Resolved
            $Record = [ordered]@{
                role = "build"
                path = $File.FullName
                length = $File.Length
                sha256 = $Hash.Hash.ToLowerInvariant()
            }
            if ($File.Extension -eq ".json") {
                Copy-Item -LiteralPath $File.FullName -Destination $EvidenceRoot -Force
                $Record.archived_as = $File.Name
            }
            $ArtifactRecords.Add($Record) | Out-Null
            $Hash
        } catch {
            "ERROR: $($_.Exception.Message)"
        }
    }
} 2>&1 | Out-String | Add-Content -Path $SummaryPath

foreach ($Path in @($IlaCsvPath) + @($StimulusLogPath)) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        continue
    }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        $Candidate = $Path
    } else {
        $Candidate = Join-Path $ProjectRoot $Path
    }
    if (Test-Path -LiteralPath $Candidate) {
        $File = Get-Item -LiteralPath $Candidate
        $Destination = Join-Path $EvidenceRoot $File.Name
        Copy-Item -LiteralPath $File.FullName -Destination $Destination -Force
        $Hash = Get-FileHash -Algorithm SHA256 -Path $Destination
        $Role = if ($File.Extension -eq ".csv") { "ila_csv" } else { "stimulus_log" }
        $ArtifactRecords.Add([ordered]@{
            role = $Role
            path = $File.FullName
            archived_as = $File.Name
            length = $File.Length
            sha256 = $Hash.Hash.ToLowerInvariant()
        }) | Out-Null
    }
}

"`r`n===== Controller-side physical 25G UDP transport NIC =====" | Add-Content -Path $SummaryPath
& {
    try {
        Get-NetAdapter -Name $InterfaceAlias | Format-List *
        Get-NetIPConfiguration -InterfaceAlias $InterfaceAlias | Format-List *
        Get-NetAdapterStatistics -Name $InterfaceAlias | Format-List *
    } catch {
        "ERROR: $($_.Exception.Message)"
    }
} 2>&1 | Out-String | Add-Content -Path $SummaryPath

$PcieDeviceRecords = [System.Collections.Generic.List[object]]::new()
"`r`n===== FPGA PCIe PF0 ${ExpectedPcieVendorId}:${ExpectedPcieDeviceId} class $ExpectedPcieClassCode =====" | Add-Content -Path $SummaryPath
$PcieEnumerationOutput = & {
    try {
        $MatchingDevices = @(Get-PnpDevice -PresentOnly | Where-Object {
            $_.InstanceId -match $PciePnpRegex
        })
        foreach ($Device in $MatchingDevices) {
            $CompatibleIds = @()
            try {
                $CompatibleIds = @(Get-PnpDeviceProperty -InstanceId $Device.InstanceId `
                    -KeyName "DEVPKEY_Device_CompatibleIds" -ErrorAction Stop).Data
            } catch {
                $CompatibleIds = @()
            }
            $ActualClassCode = $null
            foreach ($CompatibleId in $CompatibleIds) {
                $ClassMatch = [regex]::Match([string]$CompatibleId, '(?i)^PCI\\CC_([0-9A-F]{6})$')
                if ($ClassMatch.Success) {
                    $ActualClassCode = $ClassMatch.Groups[1].Value.ToUpperInvariant()
                    break
                }
            }
            $PcieDeviceRecords.Add([pscustomobject][ordered]@{
                status = [string]$Device.Status
                setup_class = [string]$Device.Class
                friendly_name = [string]$Device.FriendlyName
                instance_id = [string]$Device.InstanceId
                compatible_ids = @($CompatibleIds)
                actual_pci_class_code = $ActualClassCode
                class_code_match = ($ActualClassCode -eq $ExpectedPcieClassCode)
            }) | Out-Null
        }
        $PcieDeviceRecords | Format-List *
        if ($PcieDeviceRecords.Count -eq 0) {
            "No present PnP device matched $PciePnpPattern."
        }
    } catch {
        "ERROR: $($_.Exception.Message)"
    }
} 2>&1 | Out-String
$PcieEnumerationOutput | Add-Content -Path $SummaryPath

"`r`n===== ARP before capture =====" | Add-Content -Path $SummaryPath
& {
    try {
        arp -a
    } catch {
        "ERROR: $($_.Exception.Message)"
    }
} 2>&1 | Out-String | Add-Content -Path $SummaryPath

$Tshark = Get-Command tshark -ErrorAction SilentlyContinue
if ($null -ne $Tshark) {
    Write-Host "Capturing SFP1 ARP/UDP traffic for $CaptureSeconds seconds..."
    $TsharkArguments = @(
        "-i", $InterfaceAlias,
        "-f", "arp or udp port 28474",
        "-a", "duration:$CaptureSeconds",
        "-w", $PcapPath
    )
    & $Tshark.Source @TsharkArguments
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $PcapPath)) {
        "`r`n===== tshark capture summary =====" | Add-Content -Path $SummaryPath
        & {
            try {
                & $Tshark.Source -r $PcapPath -q -z io,stat,0
            } catch {
                "ERROR: $($_.Exception.Message)"
            }
        } 2>&1 | Out-String | Add-Content -Path $SummaryPath
    } else {
        "tshark capture failed with exit code $LASTEXITCODE." |
            Set-Content -Path (Join-Path $EvidenceRoot "pcap_failed.txt")
    }
} else {
    "tshark not installed; packet capture was skipped." |
        Set-Content -Path (Join-Path $EvidenceRoot "pcap_skipped.txt")
}

"`r`n===== Network counters after capture =====" | Add-Content -Path $SummaryPath
& {
    try {
        Get-NetAdapterStatistics -Name $InterfaceAlias | Format-List *
    } catch {
        "ERROR: $($_.Exception.Message)"
    }
} 2>&1 | Out-String | Add-Content -Path $SummaryPath

"`r`n===== ARP after capture =====" | Add-Content -Path $SummaryPath
& {
    try {
        arp -a
    } catch {
        "ERROR: $($_.Exception.Message)"
    }
} 2>&1 | Out-String | Add-Content -Path $SummaryPath

"`r`n===== Recent PCIe/PnP events =====" | Add-Content -Path $SummaryPath
& {
    try {
        $StartTime = (Get-Date).AddMinutes(-15)
        Get-WinEvent -FilterHashtable @{ LogName = "System"; StartTime = $StartTime } |
            Where-Object {
                $_.ProviderName -match "Kernel-PnP|WHEA" -or
                $_.Message -match $PciePnpRegex
            } |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message
    } catch {
        "ERROR: $($_.Exception.Message)"
    }
} 2>&1 | Out-String | Add-Content -Path $SummaryPath

$PcapPresent = Test-Path -LiteralPath $PcapPath
if ($PcapPresent) {
    $PcapFile = Get-Item -LiteralPath $PcapPath
    $PcapHash = Get-FileHash -Algorithm SHA256 -Path $PcapPath
    $ArtifactRecords.Add([ordered]@{
        role = "pcapng"
        path = $PcapFile.FullName
        archived_as = $PcapFile.Name
        length = $PcapFile.Length
        sha256 = $PcapHash.Hash.ToLowerInvariant()
    }) | Out-Null
}

$Manifest = [ordered]@{
    schema_version = 1
    timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
    computer_name = $env:COMPUTERNAME
    interface_alias = $InterfaceAlias
    transport = $TransportMetadata
    pcie_endpoint = $PcieEndpointMetadata
    capture_seconds = $CaptureSeconds
    git_commit = $GitCommit
    git_dirty = -not [string]::IsNullOrWhiteSpace($GitStatus)
    pcap_present = $PcapPresent
    artifacts = @($ArtifactRecords)
}
$Manifest.pcie_endpoint.observed_device_count = $PcieDeviceRecords.Count
$Manifest.pcie_endpoint.observed_devices = @($PcieDeviceRecords)
$Manifest.pcie_endpoint.all_observed_class_codes_match = (
    $PcieDeviceRecords.Count -gt 0 -and
    @($PcieDeviceRecords | Where-Object { -not $_.class_code_match }).Count -eq 0
)
$Manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $ManifestPath -Encoding utf8

$ZipPath = "$EvidenceRoot.zip"
Compress-Archive -Path (Join-Path $EvidenceRoot "*") -DestinationPath $ZipPath -Force
Write-Host "Evidence directory: $EvidenceRoot"
Write-Host "Evidence archive:   $ZipPath"
