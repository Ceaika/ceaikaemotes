# building and changing it

## where stuff lives

| folder | what's in it |
| --- | --- |
| `client/mods/ceaikaemotes` | mod metadata, Squirrel, wheel UI, models and paks |
| `client/.../vscripts/sh_ceaikaemotes_catalog.nut` | every emote: ID, title, sequence, timing, music track, props, pairing |
| `native/emote_visibility.cpp` | rendering, camera, lifetime checks and plugin callbacks |
| `native/emote_audio.h` | music loading and the mixer |
| `native/emote_m4a.h` | m4a decode/encode through Media Foundation |
| `native/emote_catalog.h` | the 16 old built-in track slots |
| `assets/music` | music the DLL loads, plus `tracks.txt` for every newer song |
| `assets/checksums.sha256` | hashes of the shipped music and models |
| `relay` | Python HTTP relay, tests and hosting example |
| `tools` | native build, music encoder, package validation and release packaging |

the scripts and native helper talk through private `em_native_*`, `em_audio_*` and camera convars. those aren't extra commands users need to configure. keep public commands and relay fields compatible when changing the implementation.

## asset tools

for FortnitePorting, mdlshit, studiomdl, RePak and the rest of the asset pipeline, see [asset tools and credits](asset-tools.md). those tools prepare new assets; they aren't needed to rebuild the DLL or package the existing assets below.

## building the DLL

the tested compiler is Zig 0.14.1 for Windows x64. its bundled C++ compiler produces the DLL without a separate MSVC installation. from the repo root, in PowerShell:

```powershell
.\tools\build-native.ps1 -Zig 'C:\tools\zig\zig.exe'
python -m unittest discover -s relay -v
python tools/package.py
```

the build script compiles the DLL and `encode_music.exe`, then runs the native tests. the package script checks versions, that every catalog emote has a clip and is allowed by the relay, that every song the DLL asks for exists (as a wav, or an m4a with its length trailer), asset hashes and obvious private files, before writing zips and SHA-256 checksums in `dist`. it doesn't download a compiler, install the mod, push to GitHub or deploy the VPS.

when you change music or models on purpose, check them in game, then run `python tools/package.py --checksums` to rewrite `assets/checksums.sha256`.

## adding an emote

1. port it (see [asset tools](asset-tools.md)) and put the clip in `models/emotes/<id>/anim.mdl`, included from `pilot_shared.mdl`. the titan clips go in the three chassis libraries.
2. add an entry to `sh_ceaikaemotes_catalog.nut`. there's a commented example at the bottom.
3. encode the music with `build/encode_music.exe song.wav assets/music/song.m4a` (16-bit stereo, 44.1 or 48 kHz; anything else stays a wav), then add a line to `tracks.txt`. its track number is 16 plus its line number, no DLL rebuild needed.
4. add the ID to `EMOTES` in `relay/relay.py` and deploy the relay **before** handing out the client, otherwise everyone gets a 400.

## things worth testing

native tests cover hiding/restoring entities, reused handles, attached weapons, the crouch/jump restore path, camera state, stale heartbeats and the memory cache. audio tests cover timing, panning, 44.1/48 kHz inputs and actual Windows audio-device idle/close/reopen behaviour. the m4a test encodes and decodes odd-length clips and checks the length comes back exact, with no offset. the relay tests cover all catalog IDs, pairing and joining, expiry, playback continuity, UID-only sync, removed authentication routes, request validation, room bounds and rate limits.

these aren't a replacement for launching the game. `NorthstarLauncher.exe +map mp_glitch +em_selftest quit` loads a map, plays every emote on a pilot and a titan, checks every sequence exists and the props sit where they should, prints the result to the log and quits. `+em_selftest "scan emote_x"` samples one emote at 21 points. it can't see props hiding their pieces, the music or the wheel, so look at those yourself.

for a manual check, try every wheel page, stationary and traversal emotes, jump/attack cancellation, freelook, stopping while holding crouch, turning through 0/360 degrees, and looking away from another player then back. check another client sees the normal model return. test near/far and left/right music, then stop everything and check `em_status` goes idle with zero voices.

one local client can catch compilation and local playback bugs. joining, pairs and what a friend sees need two clients over the real relay.

the compiled models are included, so rebuilding the DLL and packages does not need Blender or the original animation exports. [titans.md](titans.md) explains the retargeting work; the local porting workspace is not bundled.

## publishing

the client and Thunderstore zips have root `manifest.json`, `README.md`, `CHANGELOG.md` and a 256x256 PNG icon, plus `mods` and `plugins`. the package icon is `icon.png` in the repository root.

the Thunderstore team is chosen at upload time. the package uses `ceaikaemotes`, the version from `manifest.json` (it has to match `mod.json`), and the GitHub URL `https://github.com/Ceaika/ceaikaemotes`. it deliberately doesn't declare a stock Northstar package dependency.

review the third party asset notes before publishing. the public shared-room key is intentionally bundled. never upload private-room keys, the test profile, raw player logs, personal autoexec or production Caddyfile. the source archive is a file snapshot; it doesn't include Git history or private credentials.

official format references: [Northstar publishing](https://docs.northstar.tf/Modding/guides/publishing/), [plugin locations](https://docs.northstar.tf/Modding/plugins/), [package installation](https://docs.northstar.tf/Wiki/using-northstar/packages/), and [Thunderstore package format](https://wiki.thunderstore.io/mods/creating-a-package).
