# building and changing it

## where stuff lives

| folder | what's in it |
| --- | --- |
| `client/mods/ceaikaemotes` | mod metadata, Squirrel, wheel UI, models and paks |
| `native/emote_visibility.cpp` | rendering, camera, lifetime checks and plugin callbacks |
| `native/emote_auth.h` | fresh Origin code and HTTPS session exchange |
| `relay/identity.py` | EA verification and expiring UID-bound sessions |
| `native/emote_audio.h` | local WAV loading and mixer |
| `native/emote_catalog.h` | fixed track filenames and sample rates |
| `assets/catalog.json` | emote IDs, sequences, timing and track mapping |
| `assets/music` | music loaded by the plugin |
| `relay` | Python HTTP relay, tests and hosting example |
| `tools` | native build, package validation and release packaging |

the scripts and native helper communicate through private `em_native_*`, `em_audio_*` and camera convars. those aren't extra commands users need to configure. keep public commands and relay fields compatible when changing the implementation.

## asset tools

for FortnitePorting, mdlshit, studiomdl, RePak and the rest of the asset pipeline, see [asset tools and credits](asset-tools.md). those tools prepare new assets; they aren't needed to rebuild the DLL or package the existing assets below.

## building the DLL

the tested compiler is Zig 0.14.1 for Windows x64. its bundled C++ compiler produces the DLL without a separate MSVC installation. from the repo root, in PowerShell:

```powershell
.\tools\build-native.ps1 -Zig 'C:\tools\zig\zig.exe'
python -m unittest discover -s relay -v
python tools/package.py
```

the build script compiles the DLL and runs the native tests. the package script checks versions, catalog/audio consistency, asset hashes and obvious private files before writing zips and SHA-256 checksums in `dist`. it doesn't download a compiler, install the mod, push to GitHub or deploy the VPS.

the source archive includes the supplied runtime assets so it can build the same client. importing a brand new animation still needs the original porting pipeline and source assets; that isn't recreated from a compiled MDL by these tools. when changing assets intentionally, update `assets/checksums.sha256` after checking the changes.

`tools/emote_models.py` prepares an extracted v53 pilot MDL for dancing under a private path, preserving its geometry, materials, bones and existing animation includes. for example:

```sh
python tools/emote_models.py /path/to/extracted/cat_ears_f.mdl client/mods/ceaikaemotes/mod/models/ceaikaemotes/pilots/cat_ears_f.mdl --name ceaikaemotes/pilots/cat_ears_f.mdl
python -m unittest discover -s tools -p 'test_models.py' -v
```

Cat Ears source package versions, download URLs and hashes are recorded in `assets/cat_ears_sources.json`. extract the MDL from the listed VPK with a Titanfall VPK reader. the Pulse VPKs contain a pack log before the MDL; the model must be extracted as its own file. package validation rejects normal pilot overrides, missing private copies, wrong internal names and missing emote libraries.

## things worth testing

native tests cover hiding/restoring entities, reused handles, attached weapons, the crouch/jump restore path, camera state, stale heartbeats and the memory cache. audio tests cover timing, panning, 44.1/48 kHz inputs and actual Windows audio-device idle/close/reopen behaviour. the relay tests cover all catalog IDs, expiry, playback continuity, verified identity, rejected UID overrides, code replay, token expiry, request validation, room bounds and rate limits.

these aren't a replacement for launching the game. use an isolated profile and the game's real Squirrel compiler to check script changes. keep preview commands and private-room keys out of the release. the default shared public-room key is intentionally included in mod.json.

the actual checks and their limits for this build are in [verification.md](verification.md).

for an in-game check, try every wheel entry, stationary and traversal emotes, jump/attack cancellation, stopping while physically holding crouch, turning through 0/360 degrees, and looking away from another player then back. check another client sees the normal model return. test near/far and left/right music, then stop everything and check `em_status` goes idle with zero voices.

for Cat Ears compatibility, enable each of the four Northstar_Archive packages in turn and check its male/female Grapple or Pulse pilot before, during and after every emote. repeat with Cat Ears disabled and with all four enabled. after changing enabled mods, reload the map so model selection and precaching run again. ensure an update removed the old `mod/models/humans/pilots` overrides.

one local client can catch compilation and local playback bugs. two clients are still needed to verify what a friend sees over the real relay. don't call a single-client test proof of every multiplayer edge case.

the compiled Titan libraries are included, so rebuilding the DLL and packages does not need Blender or the original animation exports. `assets/titans.json` lists the models and `assets/titan-validation.json` records the decoded animation checks. [titans.md](titans.md) explains the retargeting work; the local porting workspace is not bundled as a portable toolchain.

## publishing

the client and Thunderstore zips have root `manifest.json`, `README.md`, `CHANGELOG.md` and a 256x256 PNG icon, plus `mods` and `plugins`. the package icon is `icon.png` in the repository root.

the Thunderstore team is chosen at upload time. the package uses `ceaikaemotes`, version `0.3.0`, and the GitHub URL `https://github.com/Ceaika/ceaikaemotes`. it deliberately doesn't declare a stock Northstar package dependency that might replace someone's Ion setup. the README explains the Ion requirement.

review the third party asset notes before publishing. the public shared-room key is intentionally bundled. never upload private-room keys, the test profile, raw player logs, personal autoexec or production Caddyfile. the source archive is a file snapshot; it doesn't include Git history or private credentials.

official format references: [Northstar publishing](https://docs.northstar.tf/Modding/guides/publishing/), [plugin locations](https://docs.northstar.tf/Modding/plugins/), [package installation](https://docs.northstar.tf/Wiki/using-northstar/packages/), and [Thunderstore package format](https://wiki.thunderstore.io/mods/creating-a-package).

0.3.0 changes authentication. deploy and check the matching relay before publishing a client that points at it. keep the in-game consent prompt, and verify both first approval and a relaunch with remembered approval. never archive session tokens.
