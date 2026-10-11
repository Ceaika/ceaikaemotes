# the relay and the VPS

the bundled room key is public. it isn't an SSH key, admin password or proof that you own a player UID. it only lets a client attempt account verification.

## what proves the account

the DLL requests a fresh, short-lived EA code through OriginSDK. after the player approves the relay, it sends that code and UID to `POST /auth`. the relay checks them with Respawn's Stryder service, including Titanfall 2 entitlement and online access. it then issues a random 30-minute emote session bound to that UID.

`POST /sync` uses that session. the server derives the UID itself and rejects a UID supplied in the body. the room key alone cannot sync an emote. used EA codes are tracked by hash to reject replays; session bearers are also stored by hash. only one session per UID stays active after reauthentication.

the code follows the existing [Atlas verifier](https://github.com/R2Northstar/Atlas/blob/main/pkg/stryder/stryder.go) and [Ion Origin-code request](https://github.com/r2ion/IonLauncher/blob/ion/src/client/origin.cpp). the native exchange uses certificate-checked HTTPS and refuses redirects. neither the client nor relay intentionally logs or stores raw EA codes.

## what the player agrees to

this still means trusting the relay with a short-lived EA credential. the first in-game prompt names the relay and explains the transfer. accepting remembers that exact address. later launches and session renewals run automatically. changing the address needs another approval. no code is sent before approval.

permission lives in the player's profile; the EA code and session token do not. **Mod Settings > ceaikaemotes > Online emotes** can forget the permission or turn syncing off. `em_auth_revoke` remains available too. this stops the client from syncing; it does not remotely invalidate a token someone already copied. that token expires on the server, and a new successful login replaces the previous session.

never paste `em_auth_session` into an issue or share raw codes. a modified client can access its own memory, so local tokens aren't protected from the person running that client.

## what's still possible

a verified player can still lie about their own selected emote or map. account verification doesn't prove which match they're in, prevent spam by real accounts, or make the VPS immune to attacks. anyone without the mod still sees the normal game model. the relay has no shell, file-browser or admin-tool endpoints.

requests have an 8192-byte body limit and a fixed emote allowlist. the room holds 32 entries and drops stale ones after six seconds. connections, timeouts, global/IP request budgets and authentication concurrency are bounded. invalid framing, unknown fields and malformed requests are rejected. these are practical limits, not a DDoS shield.

## hosting

keep the backend on loopback or a private container network, behind HTTPS. use a separate admin login. the example container is non-root, read-only, capability-free and resource-limited; it doesn't mount the Docker socket or your admin files.

only enable `--trust-proxy-header` if clients cannot reach the backend directly and your proxy overwrites `X-Emote-Client-IP`. otherwise a client can forge its apparent address. don't log outgoing Stryder URLs: the query contains the EA code. the supplied verifier redacts upstream exceptions for that reason.

the verified protocol needs both the 0.3.0 client and relay. a client download does not update a hosted backend, and legacy clients cannot use the new sessions. see [hosting](docs/hosting.md).

if you find a security bug, use the repository's private reporting channel where available. send a reproduction without credentials. the bundled public room key is already visible in mod.json; admin credentials and private-room keys are not part of the release.
