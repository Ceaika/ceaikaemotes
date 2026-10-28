# the relay and the VPS

the bundled room key is public. it isn't an SSH key, admin password or proof that you own a player UID. it only lets a client into the emote room.

## what the relay trusts

nothing proves who you are. the client sends its UID, map and emote with the room key in the `Authorization` header, and the relay takes the UID as given. there's no EA login, no OriginSDK code and no session token anymore, that all got removed in 0.3.1.

so anyone with the public key can claim any UID and make "you" dance for other mod users, or stop your emote. that's annoying but it's all they can do: the relay only stores which emote a UID is playing, and clients only draw dances for players that are actually in their match. nobody gets into your account, your game or the VPS through it.

## what's still possible

a player can lie about their UID, their emote or their map. same-map filtering doesn't prove two people are in the same server. people without the mod still see the normal game model and the server keeps control of hitboxes. the relay has no shell, file-browser or admin endpoints.

requests have an 8192-byte body limit and a fixed emote allowlist. unknown fields, bad UIDs, map names and playback IDs get rejected. the room holds 32 entries and drops stale ones after six seconds. connections, timeouts and global/per-IP request budgets are bounded. these are practical limits, not a DDoS shield.

## hosting

keep the backend on loopback or a private container network, behind HTTPS. use a separate admin login. the example container is non-root, read-only, capability-free and resource-limited; it doesn't mount the Docker socket or your admin files.

only enable `--trust-proxy-header` if clients can't reach the backend directly and your proxy overwrites `X-Emote-Client-IP`. otherwise a client can fake its address and dodge the per-IP limit. access logs don't include keys, UIDs or request bodies. see [hosting](docs/hosting.md).

if you find a security bug, use the repository's private reporting channel where available. send a reproduction without credentials. the public room key is already visible in mod.json; admin credentials and private-room keys aren't part of the release.
