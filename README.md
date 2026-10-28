# ceaikaemotes

ok so basically this lets you emote with other people who have the mod, without needing the game server to install it. there's 33 emotes for pilots and titans, two of them paired so a friend can dance with you, props like a sax and a trombone, the wheel from party pack, music that gets quieter as you walk away, and a few emotes you can walk around with.

| dancing | props | walking emotes |
| --- | --- | --- |
| ![dancing](https://raw.githubusercontent.com/Ceaika/ceaikaemotes/main/docs/media/dance.gif) | ![phone it in with the sax](https://raw.githubusercontent.com/Ceaika/ceaikaemotes/main/docs/media/prop.gif) | ![a walking emote](https://raw.githubusercontent.com/Ceaika/ceaikaemotes/main/docs/media/traversal.gif) |

this is experimental lol. **you need the Ion Client and the included DLL.** this isn't a mod that makes everyone on a vanilla client see you dancing. they need ceaikaemotes too, with the same relay and room key. the server doesn't need anything, it works on normal vanilla servers.

## installing it

close the game first. **delete your old ceaikaemotes first**, 0.5.5 got rid of a lot of files and leftovers would still get loaded:

- `R2Northstar/mods/ceaikaemotes` (whole folder)
- `R2Northstar/plugins/ceaikaemotes.dll`
- `R2Northstar/plugins/ceaikaemotes` (whole folder)

then from the client zip, put `mods/ceaikaemotes` in `R2Northstar/mods`, and put the contents of `plugins` in `R2Northstar/plugins`. the music folder goes next to the DLL, don't leave it behind.

if you install it as a Northstar package instead, keep the whole package together under `R2Northstar/packages/<package name>`. don't also install a second manual copy. the DLL uses Windows audio, so this is Windows only; Linux/Wine hasn't been checked.

the music is `.m4a` now, which Windows plays through Media Foundation. normal Windows 10/11 has it. Windows "N" editions need Microsoft's free Media Feature Pack, otherwise the emotes still work but there's no music.

## using it

the relay address and shared room key are included, and emotes are enabled by default. join a match and it syncs using your UID and the shared room key. there's no login and no EA anything, which also means UIDs aren't verified and someone could pretend to be you on the relay. Ion/Northstar needs HTTP enabled.

| key | what it does |
| --- | --- |
| hold **B** | emote wheel. scroll or **Q/E** for the other pages, release to pick, **Escape** to cancel |
| hold **H** | join the dancer standing closest to you, no need to aim |
| hold **SHIFT** | look around while emoting. the camera turns, your dancer doesn't |
| **SPACE** | stop emoting. moving stops it too, jumping, shooting and titan melee as well |

the wheel is sorted A-Z and opens on the page you left it on. all the keys can be changed in **Mod Settings > ceaikaemotes**, just type the key name (B, H, SHIFT, MOUSE3, F1, KP0...), or leave it empty to unbind. there's also a controller option (D-pad Down), an "invert up/down while looking around" toggle, and a toggle for walking emotes.

## joining and paired emotes

walk up to someone who's emoting (within about 150 units, not through walls) and hold **H**. you join their emote at the same point in the song, and the music plays like it's your own.

**Last Forever (paired)** and **Hug (paired)** need two people. start one, then your friend holds H next to you and plays the other part. for Hug, wait until your hands are up. the joiner's dancer moves to the right spot next to you, your camera stays where you stood. Hug is pilot only for now.

## titans

all the emotes except Hug work on ion, scorch, northstar, ronin, tone, legion and monarch, plus the six prime models. use the same wheel. the camera moves farther back so your titan actually fits, and the props get titan sized.

the rigs keep their own proportions. cockpit parts stay closed and the atlas fingers use their normal in-game offsets. bulky titans can still clip their arms or slide their feet a bit. this is animation retargeting, not a new collision system.

## commands

| command | what it does |
| --- | --- |
| `em_list` | every emote name |
| `em_play oj` | orange justice, or any name from `em_list` |
| `em_play billy traversal` | billy bounce while walking (crouch speed) |
| `em_stop` | stop emoting |
| `em_wheel` | open the wheel |
| `em_music 0` / `em_music 1` | turn emote music off/on |
| `em_volume 0.45` | music volume, from 0 to 1 |
| `em_enabled 0` | stop talking to the relay |
| `emkey "key"` | choose the room key |
| `em_url "https://your-host/emotes"` | use a different relay |
| `em_status` | print the useful debug bits |
| `em_probe` | check relay health |

the bundled key is public. it only picks the emote room, it isn't a VPS password or admin login. if you put a different `emkey`, `em_url` or `em_enabled 0` in your autoexec, that overrides the defaults.

## how this actually works

the relay just tells the other clients which emote you picked and how long it's been playing. their game already knows where your pilot or titan is. each client puts an animated copy there, hides the normal player model locally, and plays its own copy of the music at the right point. no audio is streamed through the VPS.

the DLL handles the bits scripts couldn't do reliably: hiding the real model and its weapons, the third person camera and the music mixer. it doesn't change `sv_cheats`, send commands to the game server, or make people without the mod see the emote.

to keep the overhead down, idle music closes its audio device and the DLL polls less often when nothing is playing. remote emotes outside your view skip their animated copies until you look back. music still works behind you.

## limitations

music doesn't get muffled by walls, and the dancing model doesn't change the server's hitbox. the DLL depends on a supported engine build. another mod replacing the same pilot or titan models will conflict with it.

## more info

- [compatibility and test coverage](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/verification.md)
- [how it works, and why](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/how-it-works.md)
- [titan retargeting](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/titans.md)
- [asset tools and credits](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/asset-tools.md)
- [building it and testing changes](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/development.md)
- [hosting a relay](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/hosting.md)
- [fixing common issues](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/troubleshooting.md)
- [what the room key does and doesn't protect](https://github.com/Ceaika/ceaikaemotes/blob/main/SECURITY.md)

## was ai used

i've used codex to get rid of the time consuming parts, such as taking the already built emotes and wheel from my partypack mod i was making, and putting them inside the standalone version; i've also used it to build the mixer and to optimize file size in 5.5

## credits and code

mod and integration by Ceaika. the animation pipeline uses FortnitePorting, UEFormat, SFM's studiomdl and mdlshit, with RePak for the wheel assets. [tools and credits](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/asset-tools.md) explains what each one does. development and debugging were AI assisted with OpenAI Codex and Claude Code. original code is MIT licensed, copyright Ceaika. the imported game models, animations and music are separate assets; the MIT license doesn't make those ours. see [third party notes](https://github.com/Ceaika/ceaikaemotes/blob/main/THIRD_PARTY_NOTICES.md).
