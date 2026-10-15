# if something doesn't work

## nobody sees the dance

both people need the scripts, models, DLL and music from the same release, and the same relay URL/key. having it installed only on your PC won't change what an unmodded client sees. the current release includes the shared key and enables emotes by default. accept the verification prompt once, or open **Mod Settings > ceaikaemotes > Online emotes > Review relay permission**. selecting a dance without permission does not send an EA code. an old autoexec can override those defaults, so check it if only one player connects. HTTP also needs to be enabled in Ion.

run `em_status`. `authState=2 sessionReady=true` means account verification completed. `native=1` means the visibility helper is available; `audioReady=1` means the music files loaded. `replyAge` should stay low while enabled and connected. `peers` counts relay entries, not necessarily rendered people in your current match. another player's UID has to match a real entity in that match.

`em_probe` checks relay health. a 401 can mean an invalid room key, a rejected EA code or an expired session, depending on the endpoint. check `authState=2` and `sessionReady=true`; sessions normally renew automatically. a legacy backend must be updated for this client. a 502 usually means the HTTPS proxy is up but can't reach the Python relay. check relay logs before changing the client.

## no music

make sure `plugins/ceaikaemotes/*.wav` is next to `plugins/ceaikaemotes.dll`. try `em_music 1` and `em_volume 0.45`, and check the game's master volume and Windows output device. this mixer uses Windows audio directly, so it isn't the campaign music volume slider.

## missing or invisible models

restart Ion after replacing the DLL. don't have both old manual and package installs enabled. other mods replacing the same pilot or titan models can conflict with the animation libraries. replace both the DLL and the complete ceaikaemotes folder when updating, including `pilot-defaults`. enable the matching Northstar_Archive Cat Ears mod and restart Ion; changing mods during a session does not regenerate cached models. stop the emote and check whether `hidden` returns to zero before reproducing it.

`em_status` reports `pilotModels=4` after successful startup preparation. `catEars` is the number of selected Cat Ears variants, from zero to four. `modelFailures` and the plugin startup log identify missing defaults, unusable VPKs or write failures. a failed Cat Ears extraction uses the stock emote model.

the upstream Cat Ears Pulse Male 1.0.0 zip has a misplaced descriptor. move `mods/pulse_cat_ears_male/Locked_Folder/mod.json` to `mods/pulse_cat_ears_male/mod.json`, next to its `vpk` folder. moving only `Locked_Folder` into your mods directory leaves the models behind.

if the native helper rejects the client build, don't remove the compatibility check to force it. its offsets need to be checked against that build first.

## FPS

compare the same view with nobody emoting, an emote visible, and the other emote outside the camera view. `em_enabled 0` stops relay activity but doesn't unload the DLL. removing the DLL for an A/B test requires closing Ion first; keep it somewhere safe so you can restore it.

when idle, expect `idle=true`, zero voices and eventually a sleeping audio worker with its device closed. active animation quality and game FPS are different things; some imported dances still have visible stepping even when the game is rendering smoothly.

## reporting it

include the client version, what you were doing, whether it happens for you or the other player, and the relevant script error plus callstack. don't include private-room keys or an entire config full of credentials. never post `em_auth_session` or raw EA codes. include the log around the actual error; startup messages alone usually won't explain a crash.
