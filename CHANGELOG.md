# release notes

## 0.4.0

- support installed Cat Ears pilot models while keeping emote animation playback on the stock pilot model paths.
- prepare Cat Ears model metadata in the cached studio section to avoid a multiplayer model-loader crash.
- restore stock pilot models when supported Cat Ears mods are disabled.

## 0.3.1

- restored stock pilot paths so emote models use the same model indices as main.
- the DLL prepares enabled Cat Ears pilot models from their installed VPKs at startup, with the same dance animation includes as the stock pilots.
- fixed generated Cat Ears metadata being placed outside the cached studio section, which could crash the model loader when entering multiplayer.
- Cat Ears meshes are no longer bundled. disabling a supported mod restores the stock model on the next Ion launch.
- install the updated DLL and complete mod folder; restart Ion after changing Cat Ears mods.

## 0.3.0

- scroll the mouse wheel to change emote pages. the bottom help text is gone.

- all 16 emotes on the seven titans and six prime models. the wheel and music work the same way as pilots.
- a farther-back titan camera, closed atlas cockpit parts and corrected finger offsets.
- titan melee cancels the dance, including traversal.
- verified EA identity for relay sessions. the shared room key no longer lets someone pick another player's UID.
- in-game permission prompt with a remembered relay address. login and renewal run automatically afterwards.
- cached player UIDs so Ion builds with noisy UID logging don't repeat it every animation frame.

**relay hosts:** update the backend before publishing the client. 0.3.0 requires verified sessions, and older clients can't sync with the new backend. see [hosting](https://github.com/Cratylel/ceaikaemotes/blob/main/docs/hosting.md).

## 0.2.1

- 16 emotes available through a two-page wheel and console commands.
- shared relay and room key configured by default, with emotes enabled on a fresh install.
- proximity music with distance fading and directional audio.
- traversal for billy bounce and griddy, using crouch-speed movement.
- local third person view and hidden attached weapons while emoting.
- offscreen animation culling and idle processing that sleeps when not needed.

see [compatibility and limitations](https://github.com/Cratylel/ceaikaemotes/blob/main/docs/verification.md) before installing, and [how it works](https://github.com/Cratylel/ceaikaemotes/blob/main/docs/how-it-works.md) for the implementation details.
