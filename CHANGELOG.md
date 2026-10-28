# 0.5.5

- way smaller: about 188 MB installed instead of about 410 MB. the client zip went from 343 MB to 99 MB.
  - animations are compressed the way the game stores its own (about 3x smaller for pilots, 7x for titans). they blend between frames now so they're a bit smoother too.
  - music is `.m4a` instead of wav, 108 MB down to 14 MB. Windows "N" editions need the Media Feature Pack for music.
  - titans dance from 3 chassis libraries (ion, northstar, scorch) instead of one per model, and the titan props reuse those clips.
  - medium titans load the dances through one shared include instead of 5 full model copies.
- emote wheel is sorted A-Z and reopens on the page you left it on.
- Mod Settings has "Invert up/down while looking around" for freelook.
- laugh and the worm music is gone (the emotes were already cut in 0.5.0).
- **delete the old mod folder, DLL and plugin folder before installing**, lots of old files are gone.
- relay: no changes, 0.5.1 is still the right one.

# 0.5.4

- props (sax, trombone, I'm A Mystery) are placed right again.
- synced emote: if the host stops, the music keeps playing for whoever is still dancing, from the same point in the song.

# 0.5.3

- props are back at the body instead of in the ground.
- synced or paired: the shared music plays like your own (centred, full volume) instead of coming from the leader's direction.

# 0.5.2

- hug partners stand close enough to actually hug, and the join prompt shows up right away.
- camera back to the normal emote camera (0.5.1's follow camera messed with the HUD and brightness).

# 0.5.1

- joining works by distance instead of aiming, the hold circle is gone.
- keys can be typed in Mod Settings. join defaults to H, space cancels.
- props no longer get stuck off the hands on other players.
- relay 0.5.1, update it together with the client.

# 0.5.0

- paired emotes: Last Forever (paired) and Hug (paired). start one, a friend joins as your partner.
- freelook: hold shift while emoting to look around without turning your dancer. joined pairs keep their facing.
- 15 new emotes, and props on pilots and titans (sax, trombone, I'm A Mystery).
- laugh and the worm are gone.
- fix: players don't stay invisible anymore after dying while emoting.
- relay 0.5.0 with the new emotes and pairing rules.

# 0.4.0

- Walk up to an emoting player and hold E for 0.8 seconds to join their current emote timing.
- A circular HUD indicator fills while holding; release, loss of sight/range, or a changed target cancels it.
- Configure the hold key in Mod Settings (E/F/R/T or Unbound).
- Keep the wheel's existing paging and selection controls.
- Relay 0.4.0 adds shared playback timing and continues supporting ordinary UID-only clients.

# 0.3.1

- Restore UID-only sync with the shared room key. UIDs are unverified.
- Remove EA authorization requests, relay verification, session tokens and login prompts.
- Update the relay alongside the client; the 0.3.0 session protocol is incompatible.

# release notes

## 0.3.0

- scroll the mouse wheel to change emote pages. the bottom help text is gone.

- all 16 emotes on the seven titans and six prime models. the wheel and music work the same way as pilots.
- a farther-back titan camera, closed atlas cockpit parts and corrected finger offsets.
- titan melee cancels the dance, including traversal.
- verified EA identity for relay sessions. the shared room key no longer lets someone pick another player's UID.
- in-game permission prompt with a remembered relay address. login and renewal run automatically afterwards.
- cached player UIDs so Ion builds with noisy UID logging don't repeat it every animation frame.

**relay hosts:** update the backend before publishing the client. 0.3.0 requires verified sessions, and older clients can't sync with the new backend. see [hosting](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/hosting.md).

## 0.2.1

- 16 emotes available through a two-page wheel and console commands.
- shared relay and room key configured by default, with emotes enabled on a fresh install.
- proximity music with distance fading and directional audio.
- traversal for billy bounce and griddy, using crouch-speed movement.
- local third person view and hidden attached weapons while emoting.
- offscreen animation culling and idle processing that sleeps when not needed.

see [compatibility and limitations](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/verification.md) before installing, and [how it works](https://github.com/Ceaika/ceaikaemotes/blob/main/docs/how-it-works.md) for the implementation details.
