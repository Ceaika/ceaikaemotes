param([Parameter(Mandatory=$true)][string]$Zig)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$native = Join-Path $repo 'native'
$build = Join-Path $repo 'build'
New-Item -ItemType Directory -Force -Path $build | Out-Null

# use the same compiler for the dll and its tests.
& $Zig c++ -target x86_64-windows-gnu -shared -O2 -std=c++17 -static -lwinmm "$native/emote_visibility.cpp" -o "$build/ceaikaemotes.dll"
if ($LASTEXITCODE -ne 0) { throw 'DLL build failed' }
foreach ($test in @('test_visibility', 'test_audio', 'test_audio_idle')) {
    & $Zig c++ -target x86_64-windows-gnu -O2 -std=c++17 -static -lwinmm -I $native "$native/tests/$test.cpp" -o "$build/$test.exe"
    if ($LASTEXITCODE -ne 0) { throw "$test build failed" }
    & "$build/$test.exe"
    if ($LASTEXITCODE -ne 0) { throw "$test failed" }
}
