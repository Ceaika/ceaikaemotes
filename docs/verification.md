# compatibility and test coverage

## current limits

both players need a Windows Northstar/Ion client, matching ceaikaemotes files and the same relay room. people without the mod see the normal player. the game server keeps control of movement and hitboxes.

the DLL depends on a checked engine layout. Linux/Wine and future game builds aren't verified. other mods replacing the same pilot or titan models will conflict. titan poses can have clipping or foot sliding. music fades with distance but isn't muffled by walls. Windows "N" editions need the Media Feature Pack for music.

relay timing isn't frame-perfect. UIDs aren't verified, so the relay can't prove who anyone is or which match they're in. the relay holds 32 room entries and the mixer has 16 voices. see [security](../SECURITY.md).

## 0.5.6, 2026-10-28

- the medium titan dances moved from `titan_medium_mp_core.mdl` (first of 9 includes) to `titan_medium_anims_workspace.mdl` (last of 9). the new file is the stock one plus one include at the end, its own 24 sequences unchanged.
- in-game self-test: 0 missing, 0 failures, poses match the 0.5.5 run within frame timing noise on every model.
- not checked yet: embark, executions and titanfall as a medium titan in a real match on a vanilla server.

## 0.5.5, 2026-10-28

what was checked:

- in-game self-test on a local map: every emote's sequence exists on pilots and titans (0 missing, 0 failures), the poses match the uncompressed clips within about 2 units, all 70 prop clips play with the prop at the right spot, no script errors.
- pumpernickel looked off in the full self-test. a 21-point scan of the old and new clip matched, it just moves so fast that one frame of timing looks huge.
- the DLL loaded all 40 tracks with 0 failures. every m4a decodes back to the exact original length with no offset, so loops stay on beat.
- native tests (visibility, audio, idle audio, m4a), 14 porter tests including one for the titan rotation scale, 24 relay tests and the package checks pass.

what wasn't checked yet:

- listening to the m4a music in game.
- the props hiding their pieces at the right time by eye. the self-test can't see bone scale, but the titan prop frames are byte for byte the chassis clips they point at.
- the A-Z wheel, remembered page and freelook invert by eye (the code is there).
- Windows N editions.

the relay is unchanged since 0.5.1 and the live one reports 0.5.1.

## 0.5.0 - 0.5.4

these were tested in real matches over the live relay, which is where most of their fixes came from: joining by distance, Last Forever and Hug pairs, props on other players, shared music after the leader stops, and the camera. the 0.5.0 relay update added the new emote IDs and pairing rules; without it the new emotes got HTTP 400.

## older notes

0.4.0 added joining another player's timing; 0.3.1 removed the EA account verification that 0.3.0 had. in 0.3.0 all 208 titan/emote combinations loaded on a local Northstar server with `sv_cheats 0`, and titan melee was checked to stop the dance and restore the model, music, crouch and camera.
