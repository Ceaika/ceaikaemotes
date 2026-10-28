# if something doesn't work

## nobody sees the dance

both people need the scripts, models, DLL and music from the same release, and the same relay URL/key. having it installed only on your PC won't change what an unmodded client sees. the release includes the shared key and enables emotes by default; **Mod Settings > ceaikaemotes > Online emotes** turns it off or on. an old autoexec can override those defaults, so check it if only one player connects. HTTP also needs to be enabled.

run `em_status`. `native=1` means the visibility helper is available; `audioReady=1` means the music loaded. `replyAge` should stay low while enabled and connected. `peers` counts relay entries, not necessarily people in your current match. another player's UID has to match a real player in that match.

a 400 from the relay usually means it doesn't know that emote yet, so the relay is older than the client. update the relay. a 401 means a wrong room key. a 502 usually means the HTTPS proxy is up but can't reach the Python relay, check the relay logs before changing the client.

## can't join someone

stand close (about 150 units), on the ground, where you can actually see them, and hold the join key (H by default) for a moment. it doesn't work through walls, while you're already emoting, or with the wheel or a menu open. Hug only takes one partner, and it doesn't work on titans.

## no music

make sure the `plugins/ceaikaemotes` folder (the `.m4a` files and `tracks.txt`) is next to `plugins/ceaikaemotes.dll`. try `em_music 1` and `em_volume 0.45`, and check the game's master volume and Windows output device. this mixer uses Windows audio directly, so it isn't the in-game music slider.

if `em_status` says `audioReady=0`, the music didn't load. on Windows "N" editions that's because Media Foundation is missing, install Microsoft's Media Feature Pack. the log says how many tracks failed.

## missing, broken or invisible models

delete the old mod folder, DLL and plugin folder before installing a new version, 0.5.5 removed a lot of files and leftovers still get loaded. restart the game after replacing the DLL. don't have both a manual and a package install enabled. another mod replacing the same pilot or titan models will conflict with the animation libraries. stop the emote and check whether `hidden` returns to zero before reproducing it.

if the native helper rejects the client build, don't remove the compatibility check to force it. its offsets need to be checked against that build first.

## FPS

compare the same view with nobody emoting, an emote visible, and the other emote outside the camera view. `em_enabled 0` stops relay activity but doesn't unload the DLL. removing the DLL for an A/B test requires closing the game first; keep it somewhere safe so you can restore it.

when idle, expect `idle=true`, zero voices and eventually a sleeping audio worker with its device closed.

## reporting it

include the client version, what you were doing, whether it happens for you or the other player, and the relevant script error plus callstack. don't include private-room keys or an entire config full of credentials. include the log around the actual error; startup messages alone usually won't explain a crash.
