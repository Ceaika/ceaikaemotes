param([Parameter(Mandatory=$true)][string]$Zig)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$native = Join-Path $repo 'native'
$build = Join-Path $repo 'build'
New-Item -ItemType Directory -Force -Path $build | Out-Null

# use the same compiler for the dll and its tests. media foundation is for the
# m4a music (emote_m4a.h), its part of windows so nothing extra ships
$libs = @('-lwinmm', '-lmfplat', '-lmfreadwrite', '-lole32')
$output = "$build/ceaikaemotes.dll"
& $Zig c++ -target x86_64-windows-gnu -shared -O2 -std=c++17 -static "$native/emote_visibility.cpp" @libs -o $output
if ($LASTEXITCODE -ne 0) { throw 'DLL build failed' }
foreach ($test in @('test_visibility', 'test_audio', 'test_audio_idle', 'test_m4a')) {
    & $Zig c++ -target x86_64-windows-gnu -O2 -UNDEBUG -std=c++17 -static -I $native "$native/tests/$test.cpp" @libs -o "$build/$test.exe"
    if ($LASTEXITCODE -ne 0) { throw "$test build failed" }
    & "$build/$test.exe"
    if ($LASTEXITCODE -ne 0) { throw "$test failed" }
}
# wav -> m4a for the music, see tools/encode_music.cpp
& $Zig c++ -target x86_64-windows-gnu -O2 -std=c++17 -static -municode "$repo/tools/encode_music.cpp" @libs -o "$build/encode_music.exe"
if ($LASTEXITCODE -ne 0) { throw 'encode_music build failed' }
