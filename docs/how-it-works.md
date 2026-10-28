# how the emotes work

## why it uses a relay

essentially the problem with a standalone emote mod is that you don't control the server you're playing on. a client mod can't just add server callbacks and expect everyone else to receive them.

ceaikaemotes uses a small HTTP relay for that part. it passes emote events between people who have the mod. the game server still handles normal movement, combat and hitboxes. people without the mod see your normal pilot, not the dance.

## what gets sent

`CeaikaEmotes_PollRelay` in `client/mods/ceaikaemotes/mod/scripts/vscripts/cl_ceaikaemotes.nut` sends a request roughly twice a second. it contains your UID, the map name, selected emote, playback ID and whether traversal is on. the room key goes in the Authorization header. while your dancer's facing is locked (freelook, a joined pair) it also sends that yaw so other people don't see it turn with your view. only one request can be in flight at a time.

the playback ID is called a nonce in the code. it just means this particular time you pressed play. restarting the same dance gets a new ID; continuing it keeps the same one. `Room.sync` in `relay/relay.py` uses that to preserve the start time instead of restarting the dance on every reply.

`CeaikaEmotes_OnRelayReply` matches received UIDs to players already in your match. positions come from the game's normal player updates. the relay doesn't send positions, animation poses or music files.

sync is approximate because requests take time to arrive. the UID isn't verified (the EA login from 0.3.0 got removed again in 0.3.1), and same-map filtering doesn't prove two people are in the same server. see [the security notes](../SECURITY.md).

## joining and pairs

holding the join key (H by default) for 0.8 seconds picks the nearest dancer within 150 units that you can actually see, no aiming. the request then carries `sync_uid` and `sync_nonce`, the dancer's UID and playback ID. the relay checks that dancer is still on the same map playing the same thing, and gives you their timeline so everyone sees you on the same beat. if they changed emote in the meantime you get a 409 and nothing happens.

`PAIRS` and `JOINS` in `relay/relay.py` are the paired emotes. joining Last Forever plays the other part on the same timeline. Hug waits for someone: the joiner starts when they join and gets the leader's timeline plus `-j`, so clients can match the two up. the joiner's dancer gets moved next to the leader using the catalog's `pairOffset`, their camera stays where they stood.

whoever joined doesn't add a second copy of the song. the shared music plays centred and full volume for both, like it's your own, and keeps going if the leader stops.

## how the player actually dances

the game normally controls a networked pilot's animation. directly assigning a dance isn't reliable because those normal updates can overwrite it. client script visibility controls also aren't enough to consistently hide that pilot.

`CeaikaEmotes_UpdateDancers` handles this by creating a clientside animated copy. it copies the pilot's model, skin, camo, bodygroups and team, while the DLL hides the original model and its attached weapons locally. copying the team preserves the matching coloured lights.

the original player still exists and keeps its normal collision and hitbox. the dancing copy is visual only, so its pose isn't a new hitbox you can shoot.

animation phase comes from elapsed playback time and the catalog's duration/rate. a copy recreated after being offscreen resumes at the current point in the dance. rotation follows the player's camera using the shortest turn, with about a 35 ms half-life to soften sudden angle changes. the real player position and your camera aren't delayed by that smoothing.

since 0.5.5 the clips are stored compressed like the game's own animations, so the engine blends between frames instead of stepping. props (the sax, the trombone, I'm A Mystery's rings) are separate clientside models playing their own clip next to the dancer, and they're hidden and shown piece by piece with bone scale.

## what the DLL handles

`native/emote_visibility.cpp` handles local visibility, attached models and the third person camera. `native/emote_audio.h` handles music. Squirrel handles the relay requests. the DLL doesn't do any networking.

the plugin uses private engine layouts, so it checks the loaded `client.dll` before using them: PE timestamp `0x5a271254`, image size `0x3d4c000`. this limits compatibility to the supported build. future client updates may require the offsets and interfaces to be checked again.

for each hidden model, the helper copies that object's renderable virtual function table and replaces its `ShouldDraw` and `DrawModel` entries. it changes individual objects in memory, not the game files on disk or every player model at once.

`HideEntity`, `RestoreEntity` and `CollectAttachedModels` check entity handles, serial numbers and attachment ownership. the engine can reuse entity slots, so an index alone isn't enough to safely restore a model. the helper tracks up to 128 hidden entities and limits how far it walks through attachments.

another engine limitation is cached visibility. restoring the original draw functions doesn't always refresh what the engine thinks is visible, so `RestoreEntity` also requests a visibility update. the script remembers cancelled playback IDs too, which prevents a delayed reply from restarting an emote that has already stopped.

render requests include a changing heartbeat. if it stops updating for roughly 750 ms, the helper restores the hidden models. VM destruction also triggers cleanup. replacing or unloading the DLL requires restarting Ion because its callbacks and audio worker belong to the loaded plugin.

## third person and traversal

`SetEmoteCamera` uses the client's camera interface for a local third person view, with collision checking and a 180-unit pilot distance or 520-unit titan distance. it saves and restores the previous custom camera data. it doesn't change `sv_cheats` or enable server cheat commands. individual servers can still have rules about client mods.

holding the freelook key (SHIFT by default) turns the camera around your dancer without turning the dancer. Mod Settings can invert up/down for it.

billy bounce, griddy, fireball, gangnam style, swagger strut and pumpernickel support traversal. the mod holds normal crouch input while they play, so movement uses crouch speed. it doesn't write a custom velocity. stopping releases the mod's own crouch input. the stop key (SPACE), jumping, attacking, titan melee or dying cancels the emote; moving also cancels stationary emotes.

## music and proximity

synchronised music needs to start at the current playback position, including when someone joins an emote partway through. seeking through game sound events wasn't reliable enough for that, so the plugin decodes local music files into memory at startup and plays them through Windows `waveOut`.

releases ship the music as AAC `.m4a`, decoded with Windows Media Foundation (`native/emote_m4a.h`). AAC pads the end of a song, which would make loops drift, so `tools/encode_music.cpp` adds a small trailer with the real length and the DLL cuts the decoded audio to exactly that. a `.wav` with the same name still wins if it's there.

`CeaikaEmotes_BuildMusicRequest` calculates playback age, gain and pan. your own emote stays stereo. other people's music is mixed to mono, then panned relative to your camera and faded with distance. the fade starts around 96 units and reaches silence at 1100 units. walls don't muffle it.

the DLL loads the 16 old built-in tracks (two slots are empty since laugh and the worm got cut) plus whatever `plugins/ceaikaemotes/tracks.txt` lists, in order. lines marked `once` are one-shot intros. the relay can't request an arbitrary filename. the mixer accepts stereo 16-bit music and outputs 48 kHz, with up to 16 simultaneous voices. gain smoothing and short edge fades help avoid clicks. four 512-frame buffers add about 43 ms of queued audio, plus device latency.

`em_music`, `em_volume` and the game's master volume control playback. when there are no voices left, the worker drains and closes the audio device, then sleeps until needed. stale requests fade out as well. no music or microphone audio is streamed through the relay, and campaign music isn't replaced.

## performance

checking engine memory repeatedly can cost a lot of CPU time. `FrameMemoryChecks` keeps up to 64 already-checked regions for the duration of one callback, so reads in the same region don't repeat the OS query. the cache is discarded each frame because the memory layout can change between frames.

player UIDs are cached by entity handle, not a reusable player slot. an unresolved UID is retried after two seconds, and destroyed entities are removed from the cache. this avoids repeated native UID calls and console spam on some Ion builds.

native polling drops to 10 Hz when idle. the dancer loop sleeps when there are no emotes, the closed wheel doesn't keep drawing, and idle music closes its audio device.

remote animated copies are skipped outside a conservative camera-frustum boundary. a margin around the model reduces popping near the screen edge. their originals stay hidden while emoting, and proximity music still works behind you. your own third person emote isn't culled this way. active emotes still have some rendering and audio cost; there isn't a guaranteed FPS figure for every PC.

## models and the wheel

pilots get the dances through one include in `models/humans/pete/pilot_shared.mdl`, which every pilot model already pulls in, and each emote's clip lives in its own `models/emotes/<id>/anim.mdl`. titans use three chassis libraries, see [titans](titans.md). nothing ships a full copy of a pilot model.

the client and UI wheel scripts use `sh_ceaikaemotes_catalog.nut`: eight sectors per page, sorted A-Z by title, and the wheel reopens on the last page you had open. the partner halves of the paired emotes aren't on the wheel, you only get those by joining. selecting an entry passes its catalog ID to the normal play command, so the wheel and console use the same relay path. orange justice uses `emote_oj`, with `oj` and `orangejustice` aliases.

wheel textures and RUI assets live under the mod's `paks` and `mod/resource` content. changing the artwork doesn't require changing the relay protocol.

for the skeleton alignment, atlas mechanical parts and grounding choices, see [titans](titans.md).
