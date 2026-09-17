param(
    [string]$MsBuildPath = '',
    [string]$Python = 'python',
    [int]$Port = 28474
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$out = Join-Path $root '.test_out'
$build = Join-Path $root '.test_build'
$dll = Join-Path $out 'leechcore_as02_rawudp_x64.dll'
$evidence = Join-Path $out 'default_transport_test.json'
$buildArgs = @{
    DefaultIp = '127.0.0.1'
    OutputDir = $out
    BuildRoot = $build
}
if ($MsBuildPath) { $buildArgs.MsBuildPath = $MsBuildPath }
& (Join-Path $root 'build_as02_leechcore.ps1') @buildArgs
if ($LASTEXITCODE -ne 0) { throw "AS02 LeechCore build failed: $LASTEXITCODE" }
& $Python (Join-Path $root 'test_as02_leechcore_default.py') '--dll' $dll '--port' $Port '--output' $evidence
if ($LASTEXITCODE -ne 0) { throw "AS02 default RawUDP probe failed: $LASTEXITCODE" }
Write-Output 'AS02_LEECHCORE_DEFAULT_TEST_PASS'
Write-Output "EVIDENCE=$evidence"
