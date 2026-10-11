# getting titans to dance

essentially a pilot animation doesn't fit a titan just because the bone names are mapped. the arms and legs start at different angles, and the proportions are completely different. throwing the same rotations on both can twist things all over the place.

## the alignment

we first tested northstar and orange justice in Blender with the Rokoko setup. the source reference limbs were aligned to the titan's reference limbs before transferring the motion. the animation's change from that aligned reference is what gets applied to the target skeleton. the titan keeps its own limb lengths.

the batch retargeting used the same relationship for the other emotes and rigs. root travel was scaled using hip-to-ground height. the reviewed northstar orange justice bake was retained, and the other clips were compiled from the transferred transforms.

there are 13 supported models: seven normal titans and six primes. some share skeletons, but their meshes don't all reach the ground at the same height. each model gets its own animation library and a constant grounding offset measured across the clip. using one constant offset keeps the jumps in the dance instead of pinning the feet to the floor every frame.

## the cockpit and fingers

the atlas bind pose isn't quite the assembled pose you see in-game. its finger translations were roughly 2.54 times the normal idle offsets, and the hatch pieces needed offsets supplied by the stock animation. leaving them in the bind pose made the hands and doors look broken.

for ion, tone, monarch and the relevant primes, the finger positions now come from the stock `a_MP_CQB_idle` pose. the dance still controls the finger rotations. hatch, eyelid and chest-laser parts use their closed idle transforms so they don't get dragged around by a human dance.

this isn't an IK system. feet can slide and bulky parts can intersect during some poses. the emote copy still has no authority over the real hitbox.

## how the models are loaded

each stock model keeps its original path, mesh and materials, with an extra animation include. custom alias paths couldn't reliably obtain model indices on the stock server, which is why the client overrides the normal paths instead. another mod replacing those models can conflict.

all sixteen clips are in each titan library. the catalog IDs and music are the same as pilots, so the relay doesn't need a separate titan event. the real player entity tells the renderer which model to use. the camera uses a 520-unit distance for titans instead of 180 for pilots, and the culling bounds are larger too.

## files and tools

- `assets/titans.json` lists the model paths and skeleton inventory.
- `assets/titan-validation.json` records library hashes and decoded pose errors.
- `client/mods/ceaikaemotes/mod/models/titans` contains the native model overrides.
- `client/mods/ceaikaemotes/mod/models/emotes/titans` contains the dance libraries.
- `cl_ceaikaemotes_models.nut` and `cl_ceaikaemotes.nut` select and render them.

the asset work used Blender/Rokoko for the initial pose setup, FortnitePorting/UEFormat for the supplied animation data, Python/NumPy for retargeting and validation, and studiomdl/mdlshit for compiling and converting. the decoded v53 frames were checked against the transferred transforms. some conversion issues needed explicit v53 frame data instead of relying on the original compressed conversion.

the release contains the compiled runtime assets. it doesn't include the original game extraction, Fortnite exports or the local porting workspace as a portable build pipeline. rebuilding the DLL/package doesn't need those tools. see [asset tools](asset-tools.md) for credits and [verification](verification.md) for what was actually tested.
