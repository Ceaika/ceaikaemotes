# the relay and the VPS

the room key only gets you into the emote API. it isn't an SSH key, shell password or admin token. the relay accepts `POST /sync` and `GET /health`; it doesn't have routes for running commands, browsing files or using the admin tool.

**but a key shared with everyone isn't proof of who sent a request.** someone with it can send an emote under another UID, fill available room slots or otherwise annoy people using that room. publishing the same key doesn't solve identity. for that we'd need an actual identity-verification system, not a longer shared password.

## what's bounded in this version

- requests have a 2048-byte body limit and a small fixed set of fields. emotes come from an allowlist; no filenames or executable commands are accepted.
- the room holds up to 32 active players, with old entries expiring after 6 seconds. reused playback IDs don't reset the clock.
- connections are limited to 16, sockets time out after 3 seconds, and global/IP token buckets limit request frequency. the IP bookkeeping itself has a size limit.
- malformed JSON, unknown fields, conflicting length headers and chunked requests are rejected. the room key is compared without an ordinary early-exit string comparison.
- the example deployment runs without root, with a read-only container filesystem, dropped capabilities and resource limits. it doesn't mount your admin directory or Docker socket.

this makes abuse more limited. it doesn't make a public VPS impossible to attack, stop bandwidth floods, or audit every other service on the machine. these limits apply to the relay code in this repository; a hosted instance may run a different version. a client update doesn't update your running relay.

## hosting rules that matter

keep the backend on loopback or a private container network. put HTTPS in front of it. don't reuse the room key as any admin credential. the client and source release deliberately include the shared emote-room key so fresh installs work together. treat it as public from this release onward. private server configs and admin credentials are still excluded.

only enable `--trust-proxy-header` when clients can't reach the backend directly and your reverse proxy overwrites `X-Emote-Client-IP`. otherwise someone can choose their own apparent IP. without that option the relay uses the connection's address; a local proxy shares the fallback bucket rather than pretending to know the end user's address.

if you host the relay alongside an admin site, keep their application routes and credentials separate. don't replace an existing Caddyfile with an example that deletes the admin site's configuration.

if you find a bug, contact the maintainer through the repository's available private reporting channel where possible. don't post private-room keys, admin credentials, request headers or unredacted configs in a public issue. the bundled public-room key is already visible in mod.json. ordinary reproduction steps without secrets are useful.
