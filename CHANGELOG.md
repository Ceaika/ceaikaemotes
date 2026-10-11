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
