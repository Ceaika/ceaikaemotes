#!/usr/bin/env bash
set -euo pipefail

# This switches sync to verified sessions. Older clients will receive 401.
source_dir=$(cd -- "$(dirname -- "$0")" && pwd)
target_dir=${1:-"$HOME/emote-relay-prototype"}
target_dir=$(cd -- "$target_dir" && pwd)
test -f "$target_dir/compose.yaml"
test -f "$target_dir/room.key"
test -f "$target_dir/relay.py"

# test before touching the running copy.
python3 -m unittest discover -s "$source_dir" -v
backup_dir=$(mktemp -d "$target_dir/before-0.3.0.XXXXXX")
cp -p "$target_dir/relay.py" "$backup_dir/relay.py"
if test -f "$target_dir/identity.py"; then cp -p "$target_dir/identity.py" "$backup_dir/identity.py"; fi
if test -f "$target_dir/limits.yaml"; then
    cp -p "$target_dir/limits.yaml" "$backup_dir/limits.yaml"
fi

rollback() {
    trap - ERR
    cp -p "$backup_dir/relay.py" "$target_dir/relay.py"
    if test -f "$backup_dir/identity.py"; then
        cp -p "$backup_dir/identity.py" "$target_dir/identity.py"
    else
        rm -f -- "$target_dir/identity.py"
    fi
    if test -f "$backup_dir/limits.yaml"; then
        cp -p "$backup_dir/limits.yaml" "$target_dir/limits.yaml"
    else
        rm -f -- "$target_dir/limits.yaml"
    fi
    local restored_compose=(-f compose.yaml)
    if test -f "$target_dir/limits.yaml"; then
        restored_compose+=(-f limits.yaml)
    fi
    (cd "$target_dir" && docker compose -p emote-relay-prototype "${restored_compose[@]}" up -d --no-deps --force-recreate relay)
    echo "Update failed. Previous relay restored. Backup: $backup_dir" >&2
}
trap rollback ERR

cp "$source_dir/relay.py" "$target_dir/relay.py"
cp "$source_dir/identity.py" "$target_dir/identity.py"
cp "$source_dir/limits.yaml" "$target_dir/limits.yaml"
cd "$target_dir"
docker compose -p emote-relay-prototype -f compose.yaml -f limits.yaml config --quiet
docker compose -p emote-relay-prototype -f compose.yaml -f limits.yaml up -d --no-deps --force-recreate relay

# check the version, not just whether something answered.
python3 - <<'PY'
import json
import time
import urllib.request

for attempt in range(15):
    try:
        with urllib.request.urlopen('http://127.0.0.1:8766/health', timeout=3) as reply:
            if json.load(reply).get('version') == '0.3.0':
                print('Relay 0.3.0 is healthy.')
                break
    except (OSError, ValueError):
        pass
    time.sleep(1)
else:
    raise SystemExit('Relay health check failed')
PY
trap - ERR
echo "Backup: $backup_dir"
echo 'Keep using -f compose.yaml -f limits.yaml for future compose changes.'
