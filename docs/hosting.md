# hosting the relay

the client comes configured for the public relay, so normal players don't need to host anything. this page is for running your own relay or updating a compatible existing deployment. the client and relay are separate components; installing a client zip doesn't update a server.

## updating a legacy relay install

**the current relay is 0.5.1, and it's the one for every 0.5.x client up to 0.5.5.** it knows all the emotes, the paired ones (Last Forever, Hug) and the locked facing for freelook. an older relay answers the new emotes with HTTP 400, so update the relay before handing out a new client. laugh and the worm stay on its allowlist so older clients don't get errors. clients from 0.3.0 that use EA sessions don't work with it.

there's no EA login, outbound Stryder verification or session storage. the relay accepts the UID in each sync request, see [SECURITY.md](../SECURITY.md).


the upgrade helper supports the legacy `emote-relay-prototype` Compose project. it expects an existing `compose.yaml`, `relay.py`, `room.key` and working service configuration. for a new install, use the setup below.

unpack the relay update outside the running installation, then run this from the new `relay` folder, using the path to your existing installation:

```bash
bash update-existing.sh "$HOME/emote-relay-prototype"
```

it runs the tests, backs up the current relay (and the old identity module if one is still there), copies the new relay module, adds resource limits and recreates only the relay container. it keeps the existing room key, Compose file, Caddyfile and admin routes. it checks that the local health endpoint reports 0.5.1, so you know the new relay is the one running and not the old one, and tries to restore the old relay if that fails. it doesn't rotate the shared key or enable trusted proxy headers automatically.

the existing service must already have working key permissions and a `.env` matching its non-root container user. the key stays read-only inside the container. don't fix a permission error by making every file world-writable.

for later restarts/config changes, keep the limits file included:

```bash
cd ~/emote-relay-prototype
docker compose -p emote-relay-prototype -f compose.yaml -f limits.yaml up -d --no-deps relay
docker compose -p emote-relay-prototype logs --tail 40 relay
curl --fail http://127.0.0.1:8766/health
```

also check your public `/emotes/health` URL after deployment, it should say `"version":"0.5.1"`. local health doesn't prove HTTPS routing works.

adding a new emote means adding its ID to `EMOTES` in `relay/relay.py` too (and to `PAIRS`/`JOINS` if it's paired), otherwise everyone gets a 400 for it.

## a new relay

on a Linux host with Docker Compose, put the `relay` folder somewhere owned by your service user. from that folder:

```bash
umask 077
python3 -c 'import secrets; from pathlib import Path; p=Path("room.key"); p.open("x").write(secrets.token_hex(24)+"\n")'
printf 'RELAY_UID=%s\nRELAY_GID=%s\n' "$(id -u)" "$(id -g)" > .env
docker compose up -d
curl --fail http://127.0.0.1:8766/health
```

exclusive creation deliberately fails if `room.key` already exists. keep your existing key when updating. this example binds only `127.0.0.1:8766` and uses Linux host networking; don't open that port to the internet. the container has a read-only filesystem, no capabilities and CPU/memory/process limits.

put the snippet in `relay/Caddyfile.example` inside your existing HTTPS site block, alongside your other routes. it strips `/emotes` before forwarding to the relay. clients then use `em_url "https://your-host/emotes"`. don't start a second proxy on occupied 80/443 ports or replace the admin site's whole config with the snippet. see Caddy's [handle_path](https://caddyserver.com/docs/caddyfile/directives/handle_path) and [reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy) docs.

the example overwrites `X-Emote-Client-IP` using the proxy connection address. if Caddy connects directly to users and the backend is private, you can add `--trust-proxy-header` to the relay command to enable per-user-IP buckets behind the proxy. don't do that if strangers can directly access the backend. if another proxy/CDN sits in front of Caddy, configure and verify that trust chain separately; blindly accepting a client-supplied IP defeats the limit.

without that option, local proxied requests share a fallback bucket. the global limit is 80 requests/second with a burst of 160, and direct/trusted individual IPs have 12/second with a burst of 24. larger groups behind one IP may need a deliberate limit change. these limits aren't a DDoS shield.

## room keys and admin

giving someone the emote key doesn't give them admin credentials. the emote process has no admin routes or shell execution feature. the room key allows `/sync` with any claimed UID. It does not prove account ownership. see [SECURITY.md](../SECURITY.md). keep the admin login separate, and don't include its configs in a client release.
