param(
    [Parameter(Mandatory = $true)]
    [string]$InterfaceAlias,

    [string]$SourceAddress = "",

    [string]$TargetAddress = "192.168.0.222",

    [ValidateRange(1, 65535)]
    [int]$UdpPort = 28474,

    [ValidateRange(0.1, 30.0)]
    [double]$TimeoutSeconds = 2.0,

    [ValidateRange(1, 100000)]
    [int]$StressIterations = 100,

    [ValidateRange(1, 184)]
    [int]$StressBatchWords = 128,

    [string]$ExpectedMac = "02-00-00-00-00-DE",

    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$SmokeTool = Join-Path $ProjectRoot "as02_udp_smoke.py"
$StressTool = Join-Path $ProjectRoot "as02_udp_stress.py"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $ProjectRoot ".tmp_sfp1_test"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $ProjectRoot $OutputDirectory
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$ProbeLog = Join-Path $OutputDirectory "sfp1_probe_$Timestamp.json"
$LoopbackLog = Join-Path $OutputDirectory "sfp1_loopback_$Timestamp.json"
$StressLog = Join-Path $OutputDirectory "sfp1_stress_$Timestamp.json"
$SummaryLog = Join-Path $OutputDirectory "sfp1_summary_$Timestamp.json"
$Result = [ordered]@{
    schema_version = 1
    timestamp = (Get-Date).ToString("o")
    success = $false
    interface_role = "controller-side physical 25G UDP transport NIC"
    pcie_endpoint_independent = $true
    interface_alias = $InterfaceAlias
    interface_description = $null
    interface_status = $null
    receive_link_speed_bps = 0
    transmit_link_speed_bps = 0
    source_address = $null
    target = "${TargetAddress}:${UdpPort}"
    expected_mac = $ExpectedMac
    observed_mac = $null
    neighbor_state = $null
    probe_log = $ProbeLog
    loopback_log = $LoopbackLog
    stress_log = $StressLog
    counters = $null
    error = $null
}

try {
    if (-not (Test-Path -LiteralPath $SmokeTool)) {
        throw "AS02 UDP smoke tool is missing: $SmokeTool"
    }
    if (-not (Test-Path -LiteralPath $StressTool)) {
        throw "AS02 UDP stress tool is missing: $StressTool"
    }
    $Python = Get-Command python -ErrorAction Stop
    $Adapter = Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop
    $Result.interface_description = $Adapter.InterfaceDescription
    $Result.interface_status = $Adapter.Status.ToString()
    $Result.receive_link_speed_bps = [uint64]$Adapter.ReceiveLinkSpeed
    $Result.transmit_link_speed_bps = [uint64]$Adapter.TransmitLinkSpeed

    if ($Adapter.Status -ne "Up") {
        throw "Interface '$InterfaceAlias' is not up (status=$($Adapter.Status))."
    }
    if ($Adapter.ReceiveLinkSpeed -lt 24000000000 -or
        $Adapter.TransmitLinkSpeed -lt 24000000000) {
        throw "Interface '$InterfaceAlias' is $($Adapter.LinkSpeed), but the AS02 image is fixed at 25.78125 Gbit/s. Use a 25G SFP28 NIC and matching optics."
    }

    $InterfaceAddresses = @(Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex `
        -AddressFamily IPv4 -ErrorAction Stop | Where-Object {
            $_.AddressState -eq "Preferred" -and $_.IPAddress -notlike "169.254.*"
        })
    if ([string]::IsNullOrWhiteSpace($SourceAddress)) {
        $TargetOctets = $TargetAddress.Split(".")
        if ($TargetOctets.Count -ne 4) {
            throw "TargetAddress must be an IPv4 address."
        }
        $TargetPrefix = "$($TargetOctets[0]).$($TargetOctets[1]).$($TargetOctets[2])."
        $Candidate = $InterfaceAddresses | Where-Object {
            $_.PrefixLength -eq 24 -and $_.IPAddress.StartsWith($TargetPrefix)
        } | Select-Object -First 1
        if ($null -eq $Candidate) {
            $SuggestedAddress = "${TargetPrefix}10"
            throw "Controller-side physical 25G NIC '$InterfaceAlias' needs a static address in the FPGA UDP endpoint /24, for example: New-NetIPAddress -InterfaceAlias '$InterfaceAlias' -IPAddress $SuggestedAddress -PrefixLength 24. This address is only for SFP1 ARP/IPv4/UDP transport and does not set the FPGA PCIe VID/DID/class."
        }
        $SourceAddress = $Candidate.IPAddress
    } else {
        $Candidate = $InterfaceAddresses | Where-Object {
            $_.IPAddress -eq $SourceAddress
        } | Select-Object -First 1
        if ($null -eq $Candidate) {
            throw "SourceAddress '$SourceAddress' is not assigned to interface '$InterfaceAlias'."
        }
    }
    $Result.source_address = $SourceAddress
    $StatisticsBefore = Get-NetAdapterStatistics -Name $InterfaceAlias

    Write-Host "AS02 SFP1 UDP transport probe: $SourceAddress -> ${TargetAddress}:${UdpPort}"
    Write-Host "PCIe endpoint identity is independent of this physical NIC IPv4 configuration."
    $ProbeOutput = & $Python.Source $SmokeTool `
        --mode probe `
        --bind $SourceAddress `
        --target $TargetAddress `
        --port $UdpPort `
        --timeout $TimeoutSeconds `
        --output $ProbeLog 2>&1
    $ProbeExitCode = $LASTEXITCODE
    $ProbeOutput | Write-Output
    if ($ProbeExitCode -ne 0) {
        throw "AS02 register probe failed; see $ProbeLog"
    }

    Start-Sleep -Milliseconds 200
    $Neighbor = Get-NetNeighbor -InterfaceIndex $Adapter.ifIndex `
        -IPAddress $TargetAddress -ErrorAction SilentlyContinue |
        Where-Object { $_.State -notin @("Unreachable", "Incomplete") } |
        Select-Object -First 1
    if ($null -eq $Neighbor) {
        throw "No usable ARP neighbor entry for $TargetAddress on '$InterfaceAlias'."
    }
    $Result.observed_mac = $Neighbor.LinkLayerAddress
    $Result.neighbor_state = $Neighbor.State.ToString()
    $ExpectedMacNormalized = $ExpectedMac.Replace("-", "").Replace(":", "").ToUpperInvariant()
    $ObservedMacNormalized = $Neighbor.LinkLayerAddress.Replace("-", "").Replace(":", "").ToUpperInvariant()
    if ($ObservedMacNormalized -ne $ExpectedMacNormalized) {
        throw "ARP MAC mismatch: expected $ExpectedMac, observed $($Neighbor.LinkLayerAddress)."
    }

    Write-Host "AS02 SFP1 loopback test"
    $LoopbackOutput = & $Python.Source $SmokeTool `
        --mode loopback `
        --loopback-value 0x11223344 `
        --bind $SourceAddress `
        --target $TargetAddress `
        --port $UdpPort `
        --timeout $TimeoutSeconds `
        --output $LoopbackLog 2>&1
    $LoopbackExitCode = $LASTEXITCODE
    $LoopbackOutput | Write-Output
    if ($LoopbackExitCode -ne 0) {
        throw "AS02 loopback test failed; see $LoopbackLog"
    }

    Write-Host "AS02 SFP1 burst, stability, and rejection suite"
    $StressOutput = & $Python.Source $StressTool `
        --bind $SourceAddress `
        --target $TargetAddress `
        --port $UdpPort `
        --timeout $TimeoutSeconds `
        --iterations $StressIterations `
        --batch-words $StressBatchWords `
        --output $StressLog 2>&1
    $StressExitCode = $LASTEXITCODE
    $StressOutput | Write-Output
    if ($StressExitCode -ne 0) {
        throw "AS02 UDP stress suite failed; see $StressLog"
    }

    $StatisticsAfter = Get-NetAdapterStatistics -Name $InterfaceAlias
    $Result.counters = [ordered]@{
        received_bytes_delta = [uint64]($StatisticsAfter.ReceivedBytes - $StatisticsBefore.ReceivedBytes)
        sent_bytes_delta = [uint64]($StatisticsAfter.SentBytes - $StatisticsBefore.SentBytes)
        received_discarded_delta = [uint64]($StatisticsAfter.ReceivedDiscardedPackets - $StatisticsBefore.ReceivedDiscardedPackets)
        received_errors_delta = [uint64]($StatisticsAfter.ReceivedPacketErrors - $StatisticsBefore.ReceivedPacketErrors)
        outbound_discarded_delta = [uint64]($StatisticsAfter.OutboundDiscardedPackets - $StatisticsBefore.OutboundDiscardedPackets)
        outbound_errors_delta = [uint64]($StatisticsAfter.OutboundPacketErrors - $StatisticsBefore.OutboundPacketErrors)
    }
    if ($Result.counters.received_discarded_delta -ne 0 -or
        $Result.counters.received_errors_delta -ne 0 -or
        $Result.counters.outbound_discarded_delta -ne 0 -or
        $Result.counters.outbound_errors_delta -ne 0) {
        throw "NIC error/discard counters increased during the AS02 test."
    }
    $Result.success = $true
} catch {
    $Result.error = $_.Exception.Message
}

$RenderedResult = $Result | ConvertTo-Json -Depth 6
$RenderedResult | Set-Content -LiteralPath $SummaryLog -Encoding utf8
$RenderedResult | Write-Output
Write-Host "AS02 SFP1 summary: $SummaryLog"

if (-not $Result.success) {
    Write-Error $Result.error
    exit 1
}

Write-Host "AS02_SFP1_NETWORK_TEST_PASS"
