# asset tools and credits

these are the tools behind the emote assets. you don't need to install them just to use ceaikaemotes. the client download already contains the compiled models, music and wheel assets.

## animations and models

| tool | what it was used for |
| --- | --- |
| [FortnitePorting](https://github.com/h4lfheart/FortnitePorting) - h4lfheart and contributors | exporting the Fortnite animations, reference skeleton and source audio. the animation pipeline takes `.ueanim` and `.uemodel` exports. |
| [UEFormat](https://github.com/h4lfheart/UEFormat) - h4lfheart and contributors | reading those exported animation/skeleton files. the porter uses the UEFormat reader from the FortnitePorting Blender plugin. |
| custom Python / NumPy scripts | mapping the animation onto the Titanfall pilot skeleton, adjusting scale and grounding, removing horizontal animation travel for traversal, and generating SMD/QC input. |
| [Source Filmmaker](https://store.steampowered.com/app/1840/Source_Filmmaker/) / `studiomdl` - Valve | compiling the SMD animation and QC definition into a Source-format animation model. the compiler is used here, not SFM's scene editor. |
| [mdlshit](https://github.com/headassbtw/mdlshit) - headassbtw, MasterLiberty and contributors | converting the compiled MDL from v49 to Titanfall's v53 format. the porter invokes its command-line mode. |
| Blender | preview scenes and renders for checking how the retargeted motion looks on the pilot models. the standard automated port doesn't need to run through a Blender scene. |

basically, exporting an emote isn't enough to make a pilot play it. the two games have different skeletons and model formats, so the motion has to be mapped onto the pilot first, then compiled and converted.

the separate Emote Porter pipeline writes explicit v53 frame sections after conversion and decodes the output to check pose errors. this handles a limitation with the converted compressed animation data. the pilot meshes and materials are reused, with animation libraries added to the models. one shared set of pilot bodies serves the whole catalog.

native pilot models were extracted with a custom Python VPK reader. [Crowbar](https://github.com/ZeqMacaw/Crowbar), by ZeqMacaw, was used as a reference for the v53 model layout; its GUI isn't a required step in this build. [RSX](https://github.com/r-ex/rsx), by r-ex and contributors, is an optional extraction tool listed in the porter's setup, not a required step in this pipeline.

only the humanoid bone animation is ported. attached Fortnite props, facial curves and VFX aren't included automatically. complex motions can still need manual retargeting adjustments; compiling successfully doesn't guarantee the pose looks right in-game.

## wheel assets

[RePak](https://github.com/r-ex/RePak), by r-ex and contributors, packages the wheel's texture atlas and UI-image entries into `ceaika_emote_wheel.rpak`.

Python with Pillow generates the ring and selection-sector images, packs them into an atlas and writes the DDS texture with mip levels. RePak then builds the RPAK that the game's RUI panels use. the emote names stay live UI text rather than being baked into the image.

## music

source audio is supplied as WAV files. the standalone packaging step uses Python's `wave` module to write a consistent RIFF header while preserving the supplied PCM samples and sample rate. it doesn't use a music-replacement sound event to play them.

at runtime the DLL mixes those local files through Windows `waveOut`. that's the playback system, not an asset export tool. see [how it works](how-it-works.md#music-and-proximity) for the proximity and sync details.

## code and build tools

Python is also used for the relay, validation and packaging. Zig's C++ compiler builds the Windows DLL. clang-format and Black are used for code formatting, and PowerShell runs the Windows build tasks. development and debugging were AI assisted with OpenAI Codex. Ion/Northstar are used for in-game checks.

the asset porter is a separate toolchain; this repository contains the compiled runtime assets and the client/relay source, not a complete copy of that porter or the original Fortnite exports. rebuilding the existing client package doesn't require rerunning the asset conversion tools.

tool credits don't change the ownership or redistribution terms of the game assets. see [third party notes](../THIRD_PARTY_NOTICES.md).
