param(
    [string]$SourceDir = (Join-Path $PSScriptRoot '..\..\..\LeechCore'),
    [string]$OutputDir = (Join-Path $PSScriptRoot 'out'),
    [string]$BuildRoot = (Join-Path $PSScriptRoot '.build'),
    [string]$MsBuildPath = '',
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [ValidateSet('x64', 'Win32', 'ARM64')]
    [string]$Platform = 'x64',
    [string]$DefaultIp = '192.168.0.222',
    [string]$ExpectedCommit = '709dce874df14e289e1c26fc18ab0b0856ae4151',
    [switch]$KeepWorktree
)

$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param([string[]]$Arguments, [string]$WorkingDirectory)
    $result = & git -C $WorkingDirectory @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed in $WorkingDirectory`n$result"
    }
    return ($result -join [Environment]::NewLine)
}

function Resolve-MsBuild {
    if ($MsBuildPath) {
        $candidate = (Resolve-Path -LiteralPath $MsBuildPath).Path
        if (Test-Path -LiteralPath $candidate) { return $candidate }
        throw "MSBuild not found: $MsBuildPath"
    }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $install = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null | Select-Object -First 1)
        if ($install) {
            $candidate = Join-Path $install.Trim() 'MSBuild\Current\Bin\MSBuild.exe'
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    $fallback = Get-ChildItem 'D:\Program Files\Microsoft Visual Studio', 'C:\Program Files\Microsoft Visual Studio' -Filter MSBuild.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\MSBuild\\Current\\Bin\\MSBuild\.exe$' } |
        Select-Object -First 1
    if ($fallback) { return $fallback.FullName }
    throw 'MSBuild with the Visual C++ toolset was not found.'
}

$SourceDir = (Resolve-Path -LiteralPath $SourceDir).Path
$PatchPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'as02_default_udp.patch')).Path
$OutputDir = [IO.Path]::GetFullPath($OutputDir)
$BuildRoot = [IO.Path]::GetFullPath($BuildRoot)
$null = [Net.IPAddress]::Parse($DefaultIp)
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path

if (-not (Test-Path -LiteralPath (Join-Path $SourceDir '.git'))) {
    throw "LeechCore source is not a Git checkout: $SourceDir"
}
$head = (Invoke-Git @('rev-parse', 'HEAD') $SourceDir).Trim()
if ($ExpectedCommit -and ($head -ne $ExpectedCommit)) {
    throw "LeechCore commit mismatch. Expected $ExpectedCommit, found $head"
}
$trackedStatus = Invoke-Git @('status', '--porcelain', '--untracked-files=no') $SourceDir
if ($trackedStatus.Trim()) {
    throw "LeechCore checkout has tracked changes; use a clean upstream checkout.`n$trackedStatus"
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$worktree = Join-Path $BuildRoot "src_$timestamp"
$logPath = Join-Path $BuildRoot "build_$timestamp.log"
$manifestPath = Join-Path $OutputDir 'as02_leechcore_manifest.json'
$worktreeAdded = $false

New-Item -ItemType Directory -Force -Path $BuildRoot, $OutputDir | Out-Null
try {
    # `git worktree add` writes its progress line to stderr even on success;
    # keep the strict PowerShell error policy while suppressing that expected
    # progress stream so a successful worktree creation reaches the build.
    Invoke-Git @('worktree', 'add', '--quiet', '--detach', $worktree, $head) $SourceDir | Out-Null
    $worktreeAdded = $true
    Invoke-Git @('apply', $PatchPath) $worktree | Out-Null

    $propsPath = Join-Path $worktree 'as02_default_rawudp.props'
    $escapedIp = $DefaultIp.Replace('&', '&amp;').Replace('"', '&quot;')
    @"
<Project>
  <ItemDefinitionGroup>
    <ClCompile>
      <PreprocessorDefinitions>AS02_DEFAULT_RAWUDP;AS02_DEFAULT_RAWUDP_IP=&quot;$escapedIp&quot;;%(PreprocessorDefinitions)</PreprocessorDefinitions>
    </ClCompile>
  </ItemDefinitionGroup>
</Project>
"@ | Set-Content -LiteralPath $propsPath -Encoding utf8

    $msbuild = Resolve-MsBuild
    $project = Join-Path $worktree 'leechcore\leechcore.vcxproj'
    $solutionDir = "$worktree\"
    $args = @(
        $project, '/t:Rebuild',
        "/p:Configuration=$Configuration", "/p:Platform=$Platform",
        "/p:SolutionDir=$solutionDir",
        "/p:CustomAfterMicrosoftCommonProps=$propsPath",
        '/m', '/v:minimal'
    )
    & $msbuild @args 2>&1 | Tee-Object -FilePath $logPath
    if ($LASTEXITCODE -ne 0) { throw "MSBuild failed with exit code $LASTEXITCODE. See $logPath" }

    $builtDll = Join-Path $worktree "files\leechcore.dll"
    if (-not (Test-Path -LiteralPath $builtDll)) { throw "Expected DLL was not produced: $builtDll" }
    $outDll = Join-Path $OutputDir "leechcore_as02_rawudp_$($Platform.ToLowerInvariant()).dll"
    $deploymentDll = Join-Path $OutputDir 'leechcore.dll'
    Copy-Item -LiteralPath $builtDll -Destination $outDll -Force
    Copy-Item -LiteralPath $builtDll -Destination $deploymentDll -Force
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PatchPath).Hash
    $dllHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $outDll).Hash
    $builderHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath).Hash
    $runnerPath = Join-Path $PSScriptRoot 'run_as02_leechcore_default_test.ps1'
    $testPath = Join-Path $PSScriptRoot 'test_as02_leechcore_default.py'
    $apiRunnerPath = Join-Path $PSScriptRoot 'run_as02_leechcore_api_test.ps1'
    $apiTestPath = Join-Path $PSScriptRoot 'test_as02_leechcore_api.py'
    $runnerHash = if (Test-Path -LiteralPath $runnerPath) { (Get-FileHash -Algorithm SHA256 -LiteralPath $runnerPath).Hash } else { $null }
    $testHash = if (Test-Path -LiteralPath $testPath) { (Get-FileHash -Algorithm SHA256 -LiteralPath $testPath).Hash } else { $null }
    $apiRunnerHash = if (Test-Path -LiteralPath $apiRunnerPath) { (Get-FileHash -Algorithm SHA256 -LiteralPath $apiRunnerPath).Hash } else { $null }
    $apiTestHash = if (Test-Path -LiteralPath $apiTestPath) { (Get-FileHash -Algorithm SHA256 -LiteralPath $apiTestPath).Hash } else { $null }
    $projectCommit = $null
    if (Test-Path -LiteralPath (Join-Path $ProjectRoot '.git')) {
        try { $projectCommit = (Invoke-Git @('rev-parse', 'HEAD') $ProjectRoot).Trim() } catch { $projectCommit = $null }
    }
    $manifest = [ordered]@{
        schema = 'as02-leechcore-build-v1'
        built_utc = (Get-Date).ToUniversalTime().ToString('o')
        source_commit = $head
        source_dir = $SourceDir
        patch = [IO.Path]::GetFileName($PatchPath)
        patch_sha256 = $patchHash
        project_root = $ProjectRoot
        project_commit = $projectCommit
        builder_sha256 = $builderHash
        runner_sha256 = $runnerHash
        test_sha256 = $testHash
        api_runner_sha256 = $apiRunnerHash
        api_test_sha256 = $apiTestHash
        configuration = $Configuration
        platform = $Platform
        default_transport = 'rawudp'
        default_ip = $DefaultIp
        udp_port = 28474
        plain_device_string = 'fpga'
        explicit_device_string = "fpga://ip=$DefaultIp"
        dll = $outDll
        deployment_dll = $deploymentDll
        dll_sha256 = $dllHash
        build_log = $logPath
        msbuild = $msbuild
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    Write-Output "AS02_LEECHCORE_BUILD_PASS"
    Write-Output "DLL=$outDll"
    Write-Output "DEPLOYMENT_DLL=$deploymentDll"
    Write-Output "SHA256=$dllHash"
    Write-Output "MANIFEST=$manifestPath"
}
finally {
    if ($worktreeAdded -and -not $KeepWorktree) {
        try { Invoke-Git @('worktree', 'remove', '--force', $worktree) $SourceDir | Out-Null } catch { Write-Warning $_ }
    }
}
