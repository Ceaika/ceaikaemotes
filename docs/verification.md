# compatibility and test coverage

## current limitations

- both players need ceaikaemotes, a supported Windows Ion client and access to the same relay room. unmodded players don't see the animated copies.
- the DLL depends on a particular engine layout. its build check rejects unsupported layouts; Linux/Wine compatibility hasn't been verified.
- emotes are visual copies. the game server still uses the original player's movement, animation state and hitbox.
- relay timing isn't frame-perfect, and the shared public key doesn't verify player identity. see [SECURITY.md](../SECURITY.md).
- some imported animations can look stepped. proximity audio fades with distance but doesn't account for walls.
- the supplied relay supports up to 32 active room entries. the audio mixer supports 16 simultaneous voices. large public groups may need a different relay capacity or room design.
- other mods replacing the same pilot models can conflict with the animation libraries.

## automated checks

the native tests cover model restoration, reused entity handles, attachments, camera state, stale heartbeats and the per-frame memory cache. audio checks cover playback timing, panning, sample rates and Windows audio-device sleep/reopen behaviour.

the 12 relay tests cover catalog entries, traversal restrictions, authentication, expiry, timing continuity, malformed requests, room capacity and request limits. packaging checks validate catalog/audio mappings, asset hashes, icon size, versions and ZIP integrity.

## in-game coverage

the release was checked with an isolated Ion client on a local Northstar server using `sv_cheats 0`. all 16 emotes produced an animated copy and an active music voice without client script errors. wheel selection, including orange justice, was checked in-game, along with a griddy traversal request.

after stopping, the client returned to zero animated copies, hidden entities and audio voices, with the audio device closed. the bundled public-room key was also checked against the hosted relay.

this release check used one game client. it doesn't cover every multiplayer timing issue, hardware setup or server combination, and it isn't a performance benchmark. the deployment script has passed Bash syntax checks, but the Docker/Caddy deployment hasn't been exercised as part of this release check.

for contributor commands and an in-game checklist, see [development.md](development.md). for installation problems, see [troubleshooting.md](troubleshooting.md).
