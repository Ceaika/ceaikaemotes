# compatibility and test coverage

## current limits

both players need a supported Windows Ion client, matching ceaikaemotes files and the same relay room. people without the mod see the normal player. the game server keeps control of movement and hitboxes. Cat Ears pilot mods use matching dancing copies; other custom pilot meshes use standard dancing copies.

the DLL depends on a checked engine layout. Linux/Wine and arbitrary future builds aren't verified. other mods replacing the same pilot or titan models can conflict. some dances look stepped even at high FPS, and titan poses can have clipping or foot sliding. music fades with distance but isn't muffled by walls.

relay timing isn't frame-perfect. identity verification doesn't prove match membership or that someone is honest about their own emote. the supplied relay has 32 room entries and the mixer has 16 voices. see [security](../SECURITY.md).

## checked before packaging

native tests cover visibility restoration, reused handles, attachments, camera state, stale requests and idle processing. audio tests cover phase, panning, supported sample rates and closing/reopening the Windows device. authentication checks cover consent gating, URL restrictions, callback errors and clearing sessions.

relay tests cover catalog/traversal restrictions, replay and expiry, rejection of UID overrides, malformed requests, capacity and request limits. packaging checks validate versions, icon dimensions, catalog/audio mappings, model hashes, archive paths and ZIP integrity. native model checks cover stock paths, enabled and disabled mods, duplicate enabled versions, malformed input, animation includes, source preservation and restoring pristine defaults. packaging checks ensure generated Cat Ears meshes are replaced by pristine stock assets in archives.

the native preparation code was exercised with all four published Cat Ears packages after checking their archive and source MDL hashes. each output preserves the original mesh data, uses the requested stock model name and includes all 16 emote libraries. disabling all four restores byte-identical main models. the native test passes on Linux with address/undefined-behaviour sanitizers, and the Windows DLL cross-compiles. a regression test now reads includes and the model name from the studio metadata section alone, excluding the separately loaded packed payloads. it failed with the original generator, which appended this metadata after the payloads. the corrected generator keeps the metadata resident and preserves the PHY/VTX/VVD/VVC bytes and alignment; this was also checked on all four published sources. the reported `datacache.dll` crash occurred with the earlier layout. the corrected build has not yet been checked in Ion; these checks do not prove in-game loading, playback or camera behavior.

all 208 titan/emote combinations loaded in an isolated Ion client on a local Northstar server with `sv_cheats 0`. after correcting atlas mechanical bones and prime grounding, the affected seven rigs passed another 112 playback checks. stopping returned hidden entities and animated copies to zero. northstar orange justice and the corrected atlas hands/cockpit were also visually reviewed.

real titan melee input was checked with orange justice and traversal griddy. both stopped and restored the model, music, forced crouch and camera without script errors.

a real EA-code exchange passed against the HTTPS preview relay. the single-client checks rejected a forged sync UID, invalid session, public key used as a session and fake EA code. a separate native probe requested a fresh code for the real account but submitted it with a different dummy UID; that was rejected with HTTP 401. these checks don't require another player and don't expose raw credentials.

the in-game relay prompt was accepted and wheel playback confirmed without console commands. remembered permission also authenticated automatically on a subsequent isolated-client launch. mouse-wheel page switching and removal of the bottom help text were checked in-game too.
