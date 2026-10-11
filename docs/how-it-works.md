# how the emotes work

## why it uses a relay

essentially the problem with a standalone emote mod is that you don't control the server you're playing on. a client mod can't just add server callbacks and expect everyone else to receive them.

ceaikaemotes uses a small HTTP relay for that part. it passes emote events between people who have the mod. the game server still handles normal movement, combat and hitboxes. people without the mod see your normal pilot, not the dance.

## what gets sent

`CeaikaEmotes_PollRelay` in `client/mods/ceaikaemotes/mod/scripts/vscripts/cl_ceaikaemotes.nut` sends a request roughly twice a second. it contains the map name, selected emote, playback ID and whether traversal is on. the session token goes in the Authorization header. the relay gets your UID from that session; a UID in the sync body is rejected. only one request can be in flight at a time.

the playback ID is called a nonce in the code. it just means this particular time you pressed play. restarting the same dance gets a new ID; continuing it keeps the same one. `Room.sync` in `relay/relay.py` uses that to preserve the start time instead of restarting the dance on every reply.

`CeaikaEmotes_OnRelayReply` matches received UIDs to players already in your match. positions come from the game's normal player updates. the relay doesn't send positions, animation poses or music files.

sync is approximate because requests take time to arrive. account verification proves the UID, but same-map filtering still doesn't prove two people are in the same server. see [the security notes](../SECURITY.md).

## account verification

the first time you join, the UI asks whether you trust the configured relay. accepting saves that exact address in your profile. future launches authenticate automatically, and a different address needs another approval. the old console commands still work but aren't required.

`native/emote_auth.h` asks OriginSDK for a fresh `TITANFALL2-PC-SERVER` code. it doesn't borrow the token Ion is already using. a worker sends the code and UID to `/auth` over HTTPS, with redirects refused. `relay/identity.py` verifies the pair through Respawn's Stryder service and checks entitlement and online access. this follows the mechanism used by Atlas.

the relay gives back a random session token valid for 30 minutes. the script renews a little before expiry. the relay stores a hash of the token and a short-lived hash of each used code, not the raw credentials. errors or an unavailable authority don't fall back to trusting a UID from the client.

the room key only permits an authentication attempt. it isn't the session token. anyone can know that public key without gaining an emote session for your account. the relay still receives a short-lived EA credential during login, so the approval is an actual trust decision.

## how the player actually dances

the game normally controls a networked pilot's animation. directly assigning a dance isn't reliable because those normal updates can overwrite it. client script visibility controls also aren't enough to consistently hide that pilot.

`CeaikaEmotes_UpdateDancers` handles this by creating a clientside animated copy. it copies the pilot's model, skin, camo, bodygroups and team, while the DLL hides the original model and its attached weapons locally. copying the team preserves the matching coloured lights.

the original player still exists and keeps its normal collision and hitbox. the dancing copy is visual only, so its pose isn't a new hitbox you can shoot.

animation phase comes from elapsed playback time and the catalog's duration/rate. a copy recreated after being offscreen resumes at the current point in the dance. rotation follows the player's camera using the shortest turn, with about a 35 ms half-life to soften sudden angle changes. the real player position and your camera aren't delayed by that smoothing.

some imported animations can look a bit stepped even at high game FPS. smoother frame rendering doesn't add extra detail to the source animation.

## what the DLL handles

`native/emote_visibility.cpp` handles local visibility, attached models and the third person camera. `native/emote_audio.h` handles music. Squirrel handles normal sync requests. `native/emote_auth.h` handles the initial EA-code exchange through Windows WinHTTP, keeping the raw code out of scripts, console variables and logs.

the plugin uses private engine layouts, so it checks the loaded `client.dll` before using them: PE timestamp `0x5a271254`, image size `0x3d4c000`. this limits compatibility to the supported build. future client updates may require the offsets and interfaces to be checked again.

for each hidden model, the helper copies that object's renderable virtual function table and replaces its `ShouldDraw` and `DrawModel` entries. it changes individual objects in memory, not the game files on disk or every player model at once.

`HideEntity`, `RestoreEntity` and `CollectAttachedModels` check entity handles, serial numbers and attachment ownership. the engine can reuse entity slots, so an index alone isn't enough to safely restore a model. the helper tracks up to 128 hidden entities and limits how far it walks through attachments.

another engine limitation is cached visibility. restoring the original draw functions doesn't always refresh what the engine thinks is visible, so `RestoreEntity` also requests a visibility update. the script remembers cancelled playback IDs too, which prevents a delayed reply from restarting an emote that has already stopped.

render requests include a changing heartbeat. if it stops updating for roughly 750 ms, the helper restores the hidden models. VM destruction also triggers cleanup. replacing or unloading the DLL requires restarting Ion because its callbacks and audio worker belong to the loaded plugin.

## third person and traversal

`SetEmoteCamera` uses the client's camera interface for a local third person view, with collision checking and a 180-unit pilot distance or 520-unit titan distance. it saves and restores the previous custom camera data. it doesn't change `sv_cheats` or enable server cheat commands. individual servers can still have rules about client mods.

billy bounce and griddy support traversal. the mod holds normal crouch input while they play, so movement uses crouch speed. it doesn't write a custom velocity. stopping releases the mod's own crouch input. jumping, attacking, titan melee or dying cancels the emote; moving also cancels stationary emotes.

## music and proximity

synchronised music needs to start at the current playback position, including when someone joins an emote partway through. seeking through game sound events wasn't reliable enough for that, so the plugin uses local WAV files through Windows `waveOut`.

`CeaikaEmotes_BuildMusicRequest` calculates playback age, gain and pan. your own emote stays stereo. other people's music is mixed to mono, then panned relative to your camera and faded with distance. the fade starts around 96 units and reaches silence at 1100 units. walls don't muffle it.

the DLL loads a fixed list of 16 tracks. the relay can't request an arbitrary filename. the mixer accepts the supplied 44.1 and 48 kHz stereo PCM files and outputs 48 kHz, with up to 16 simultaneous voices. gain smoothing and short edge fades help avoid clicks. four 512-frame buffers add about 43 ms of queued audio, plus device latency.

`em_music`, `em_volume` and the game's master volume control playback. when there are no voices left, the worker drains and closes the audio device, then sleeps until needed. stale requests fade out as well. no music or microphone audio is streamed through the relay, and campaign music isn't replaced.

## performance

checking engine memory repeatedly can cost a lot of CPU time. `FrameMemoryChecks` keeps up to 64 already-checked regions for the duration of one callback, so reads in the same region don't repeat the OS query. the cache is discarded each frame because the memory layout can change between frames.

player UIDs are cached by entity handle, not a reusable player slot. an unresolved UID is retried after two seconds, and destroyed entities are removed from the cache. this avoids repeated native UID calls and console spam on some Ion builds.

native polling drops to 10 Hz when idle. the dancer loop sleeps when there are no emotes, the closed wheel doesn't keep drawing, and idle music closes its audio device.

remote animated copies are skipped outside a conservative camera-frustum boundary. a margin around the model reduces popping near the screen edge. their originals stay hidden while emoting, and proximity music still works behind you. your own third person emote isn't culled this way. active emotes still have some rendering and audio cost; there isn't a guaranteed FPS figure for every PC.

## models and the wheel

pilot and titan models are shared across the emote catalog, with separate animation libraries for the dances. this avoids bundling a complete set of pilot models for every emote. source animation quality isn't reduced to make that saving.

the client and UI wheel scripts use `sh_ceaikaemotes_catalog.nut`: eight sectors per page, two pages. selecting an entry passes its catalog ID to the normal play command, so the wheel and console use the same relay path. orange justice uses `emote_oj`, with `oj` and `orangejustice` aliases.

wheel textures and RUI assets live under the mod's `paks` and `mod/resource` content. changing the artwork doesn't require changing the relay protocol.

for the skeleton alignment, atlas mechanical parts and grounding choices, see [titans](titans.md).
