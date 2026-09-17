param(
    [string]$MsBuildPath = '',
    [int]$Port = 28474,
    [double]$TimeoutSeconds = 30,
    [string]$Python = 'python'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$out = Join-Path $root '.test_out'
$build = Join-Path $root '.test_build'
$dll = Join-Path $out 'leechcore_as02_rawudp_x64.dll'
$output = Join-Path $out 'api_mock_test.json'
$buildArgs = @{
    DefaultIp = '127.0.0.1'
    OutputDir = $out
    BuildRoot = $build
}
if ($MsBuildPath) { $buildArgs.MsBuildPath = $MsBuildPath }
& (Join-Path $root 'build_as02_leechcore.ps1') @buildArgs
if ($LASTEXITCODE -ne 0) {
    throw "AS02 LeechCore build failed with exit code $LASTEXITCODE"
}
$args = @(
    (Join-Path $root 'test_as02_leechcore_api.py'),
    '--dll', $dll,
    '--port', $Port,
    '--timeout', $TimeoutSeconds,
    '--output', $output
)
& $Python @args
if ($LASTEXITCODE -ne 0) {
    throw "AS02 LeechCore API mock test failed with exit code $LASTEXITCODE"
}
Write-Output "AS02_LEECHCORE_API_TEST_PASS"
Write-Output "EVIDENCE=$output"
