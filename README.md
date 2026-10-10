# ceaikaemotes

ok so basically this lets you emote with other people who have the mod, without needing the game server to install it. there's 16 emotes, the wheel from party pack, music that gets quieter as you walk away, and traversal for billy bounce and griddy.

this is experimental lol. **you need Ion and the included DLL.** this isn't a mod that makes everyone on a vanilla client see you dancing. they need ceaikaemotes too, with the same relay and room key.

## installing it

close the game first. from the client zip, put `mods/ceaikaemotes` in `R2Northstar/mods`, and put the contents of `plugins` in `R2Northstar/plugins`. the WAV folder goes next to the DLL, don't leave it behind. replace your old ceaikaemotes folder when updating rather than keeping two copies.

if you install it as a Northstar package instead, keep the whole package together under `R2Northstar/packages/<package name>`. don't also install a second manual copy. the native helper uses Windows audio, so this release is for Windows Ion; Linux/Wine behaviour hasn't been verified here.

the relay URL and shared room key are already included, and emotes are enabled by default. install it, launch Ion and join your friends in the same match. nobody needs to type `emkey` or `em_enabled 1` on a fresh install. Ion still needs HTTP enabled so it can reach the relay.

the bundled key is public. it only selects/accesses the emote room, it isn't a VPS password or admin login. if you previously put a different `emkey`, `em_url` or `em_enabled 0` in your autoexec, that will override these defaults. you can still use those commands for another relay or to turn this one off. these settings don't have archive flags, so persistent custom settings belong in your own autoexec.

hold **B** for the wheel, use **Q/E** for the other page, release to choose, or **Escape** to cancel. the mod settings have wheel controls and a traversal toggle. only billy bounce and griddy can move, and they use crouch speed. jumping or attacking stops the emote.

## rebinding the wheel

in **Mod Settings > ceaikaemotes > Emote wheel controls**, choose B, G, H or J for hold-to-open, or enable D-pad Down for a controller. you can also set either control to Unbound.

for another keyboard key, bind the console command, for example:

```text
bind "F4" "em_wheel"
```

that opens the wheel with a tap, then you click an emote. it doesn't use release-to-select. arbitrary hold-to-open bindings aren't supported currently.

## commands

| command | what it does |
| --- | --- |
| `em_play oj` | orange justice. `em_list` shows all the other names |
| `em_play billy traversal` | billy bounce while moving slowly |
| `em_play griddy traversal` | same thing for griddy |
| `em_stop` | stop emoting |
| `em_wheel` | open the wheel |
| `em_music 0` / `em_music 1` | turn emote music off/on |
| `em_volume 0.45` | music volume, from 0 to 1 |
| `em_enabled 0` | stop relay participation |
| `emkey "key"` | choose the room key |
| `em_url "https://your-host/emotes"` | use a different relay |
| `em_status` | print the useful debug bits |
| `em_probe` | check relay health |

## how this actually works

the relay just tells the other clients which emote you picked and how long it's been playing. their game already knows where your pilot is. each client puts an animated copy there, hides the normal pilot locally, and plays its own copy of the music at the right point. no audio files are being streamed through the VPS.

the DLL handles the bits scripts couldn't do reliably: hiding the real model and its weapons, the local third person camera, and the music mixer. it doesn't change `sv_cheats`, send commands to the game server, or make people without the mod see the emote.

to keep the overhead down, idle music closes its audio device and the DLL polls less often when nothing is playing. memory checks are reused within each frame, and remote emotes outside your view skip their animated copies until you look back. music still works behind you.

## limitations

some animations can look stepped even at high FPS, music doesn't get muffled by walls, and the dancing model doesn't change the server's hitbox. the DLL also depends on a supported engine build. another mod replacing the same pilot models can conflict with it.

## more info

these pages explain the setup, the engine limitations behind the design, and what's currently supported:

- [compatibility and test coverage](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/verification.md)
- [how it works, and why](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/how-it-works.md)
- [asset tools and credits](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/asset-tools.md)
- [building it and testing changes](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/development.md)
- [hosting a relay](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/hosting.md)
- [fixing common issues](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/troubleshooting.md)
- [what the room key does and doesn't protect](https://github.com/Ceaika/ceaikaemotes/blob/main/SECURITY.md)

## was ai used

i've used codex to get rid of the time consuming parts, such as taking the already built emotes and wheel from my partypack mod i was making, and putting them inside the standalone version; i've also used it to build the mixer.

## credits and code

mod and integration by Ceaika. the animation pipeline uses FortnitePorting, UEFormat, SFM's studiomdl and mdlshit, with RePak for the wheel assets. [tools and credits](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/asset-tools.md) explains what each one does. development and debugging were AI assisted with OpenAI Codex. original code is MIT licensed, copyright Ceaika. the imported game models, animations and music are separate assets; the MIT license doesn't make those ours. see [third party notes](https://github.com/Ceaika/ceaikaemotes/blob/main/THIRD_PARTY_NOTICES.md).
