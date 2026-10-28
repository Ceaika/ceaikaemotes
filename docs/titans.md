# getting titans to dance

essentially a pilot animation doesn't fit a titan just because the bone names are mapped. the arms and legs start at different angles, and the proportions are completely different. throwing the same rotations on both can twist things all over the place.

## the alignment

we first tested northstar and orange justice in Blender with the Rokoko setup. the source reference limbs were aligned to the titan's reference limbs before transferring the motion. the animation's change from that aligned reference is what gets applied to the target skeleton. the titan keeps its own limb lengths.

the batch retargeting used the same relationship for the other emotes and rigs. root travel was scaled using hip-to-ground height. using one constant grounding offset per clip keeps the jumps in the dance instead of pinning the feet to the floor every frame.

## the cockpit and fingers

the atlas bind pose isn't quite the assembled pose you see in-game. its finger translations were roughly 2.54 times the normal idle offsets, and the hatch pieces needed offsets supplied by the stock animation. leaving them in the bind pose made the hands and doors look broken.

for the atlas chassis, the finger positions come from the stock `a_MP_CQB_idle` pose. the dance still controls the finger rotations. hatch, eyelid and chest-laser parts use their closed idle transforms so they don't get dragged around by a human dance.

this isn't an IK system. feet can slide and bulky parts can intersect during some poses. the emote copy still has no authority over the real hitbox.

## how the models are loaded

there are 13 supported models: seven normal titans and six primes. they come in three chassis, and since 0.5.5 each chassis has one dance library instead of one per model:

| library | titans |
| --- | --- |
| `models/emotes/titans/ion.mdl` | ion, tone, monarch, ion prime, tone prime |
| `models/emotes/titans/northstar.mdl` | northstar, ronin, northstar prime, ronin prime |
| `models/emotes/titans/scorch.mdl` | scorch, legion, scorch prime, legion prime |

the medium titans (atlas chassis) all include `models/titans/medium/titan_medium_mp_core.mdl`, the same way every pilot includes `pilot_shared.mdl`, so that one 1.8 MB file is the only override for all five of them. light and heavy titans still override their full models at the stock paths, because their stock include libraries are LZHAM compressed inside the VPKs and we couldn't get them out cleanly yet. another mod replacing those models will conflict.

custom alias paths couldn't reliably get model indices on a vanilla server, which is why the client overrides stock paths instead of adding new ones. the props do the same thing: the sax, trombone and I'm A Mystery's rings sit on five unused `models/test/brad/store_*` paths.

all the emotes except Hug are in every library. the catalog IDs and music are the same as pilots, so the relay doesn't need a separate titan event. the real player entity tells the renderer which model to use. the camera uses a 520-unit distance for titans instead of 180 for pilots, and the culling bounds are larger too.

## compression

the libraries are stored the way the game stores its own animations (v53 RLE tracks with a rotation scale), which made them about 7x smaller and lets the engine blend between frames. fun fact that cost a whole night: the game reads that rotation scale from the linear bone table, not from the per-bone struct, so patching only the struct bent every titan over like an old man.

the prop models can't use that compression, they hide pieces with animated bone scale and the compressor doesn't write scale tracks. instead the ten non-chassis titan clips in each prop just point at their chassis clip's frames, which halved their size.

## files

- `client/mods/ceaikaemotes/mod/models/titans` has the model overrides.
- `client/mods/ceaikaemotes/mod/models/emotes/titans` has the three dance libraries.
- `cl_ceaikaemotes_models.nut` and `cl_ceaikaemotes.nut` pick and render them.

the asset work used Blender/Rokoko for the initial pose setup, FortnitePorting/UEFormat for the supplied animation data, Python/NumPy for retargeting and validation, and studiomdl/mdlshit for compiling and converting.

the release contains the compiled runtime assets. it doesn't include the original game extraction, Fortnite exports or the local porting workspace. rebuilding the DLL/package doesn't need those tools. see [asset tools](asset-tools.md) for credits and [verification](verification.md) for what was actually tested.
