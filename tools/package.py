"""Validate the release inputs and build client, source and relay archives.

python tools/package.py --checksums rewrites assets/checksums.sha256 after
you changed music or models on purpose.
"""

import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import sys
import wave
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
VERSION = json.loads((ROOT / "manifest.json").read_text())["version_number"]
MOD = ROOT / "client/mods/ceaikaemotes"
MUSIC = ROOT / "assets/music"
CHECKSUMS = ROOT / "assets/checksums.sha256"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def release_files(folder):
    for path in sorted(folder.rglob("*")):
        if path.is_file() and "__pycache__" not in path.parts:
            yield path


def catalog_ids():
    # the commented out example at the bottom starts with // so it doesnt match
    catalog = (MOD / "mod/scripts/vscripts/sh_ceaikaemotes_catalog.nut").read_text()
    return re.findall(r'^\s*def\.id = "([^"]+)"', catalog, re.M)


def music_names():
    # the 16 old built-in slots first, then whatever tracks.txt adds
    names = re.findall(r'L"ceaikaemotes\\\\([^"]+)"', (ROOT / "native/emote_catalog.h").read_text())
    for line in (MUSIC / "tracks.txt").read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            names.append(line.split()[0])
    return names


def check_music(name):
    # the DLL tries the wav first and falls back to an m4a with the same name
    wav = MUSIC / name
    if wav.is_file():
        with wave.open(str(wav), "rb") as audio:
            assert audio.getnchannels() == 2 and audio.getsampwidth() == 2, name
            assert audio.getnframes() > 0, name
        return
    m4a = wav.with_suffix(".m4a")
    assert m4a.is_file(), f"Missing music: {name}"
    # without the trailer the DLL cant cut the aac padding and the loop drifts
    trailer = m4a.read_bytes()[-24:]
    assert trailer[4:16] == b"freeceaikafr", f"{m4a.name} has no length trailer"
    assert struct.unpack("<Q", trailer[16:])[0] > 0, m4a.name


def checksum_files():
    yield from release_files(MUSIC)
    yield from release_files(MOD / "mod/models")


def write_checksums():
    lines = [f"{digest(path)}  {path.relative_to(ROOT).as_posix()}" for path in checksum_files()]
    CHECKSUMS.write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")
    print(f"{len(lines)} checksums written")


def validate():
    manifest = json.loads((ROOT / "manifest.json").read_text())
    mod = json.loads((MOD / "mod.json").read_text())
    assert mod["Version"] == VERSION
    assert re.fullmatch(r"\d+\.\d+\.\d+", VERSION)
    assert len(manifest["description"]) <= 250
    assert manifest["website_url"] == "https://github.com/Ceaika/ceaikaemotes"
    convars = {item["Name"]: item["DefaultValue"] for item in mod["ConVars"]}
    assert re.fullmatch(r"[a-zA-Z0-9_-]{24,128}", convars["emkey"])
    assert convars["em_enabled"] == "1"
    assert not any(name.startswith("em_auth_") for name in convars)
    assert not any(item["Name"].startswith("em_auth_") for item in mod["ConCommands"])
    assert not (ROOT / "native/emote_auth.h").exists()
    assert not (ROOT / "relay/identity.py").exists()

    # an emote the relay doesnt know just 400s for everyone
    relay = (ROOT / "relay/relay.py").read_text()
    models = MOD / "mod/models"
    ids = catalog_ids()
    assert ids and len(ids) == len(set(ids))
    for ident in ids:
        assert f'"{ident}"' in relay, f"Relay doesn't allow {ident}"
        assert (models / "emotes" / ident / "anim.mdl").is_file(), ident
    for chassis in ("ion", "northstar", "scorch"):
        assert (models / "emotes/titans" / f"{chassis}.mdl").is_file(), chassis
    # the medium titan dances have to hang off their LAST include. on mp_core
    # (0.5.5) they shifted every vanilla anim number after it and the server
    # picks anims by number, so embarks and executions played the wrong thing
    medium = models / "titans/medium"
    assert sorted(p.name for p in medium.iterdir()) == ["titan_medium_anims_workspace.mdl"]
    for name in music_names():
        check_music(name)

    listed = {}
    for line in CHECKSUMS.read_text().splitlines():
        expected, relative = line.split("  ", 1)
        listed[relative] = expected
    for path in checksum_files():
        relative = path.relative_to(ROOT).as_posix()
        assert listed.pop(relative, None) == digest(path), f"Asset changed: {relative}"
    assert not listed, f"Assets gone: {sorted(listed)}"

    icon = (ROOT / "icon.png").read_bytes()
    assert icon[:8] == b"\x89PNG\r\n\x1a\n"
    assert struct.unpack(">II", icon[16:24]) == (256, 256)
    dll = ROOT / "build/ceaikaemotes.dll"
    assert dll.is_file() and dll.read_bytes()[:2] == b"MZ", "Build the DLL first"
    binary = dll.read_bytes()
    for marker in (b"OriginRequestAuthCode", b"OriginSDK.dll", b"WINHTTP.dll", b"em_auth_request"):
        assert marker.lower() not in binary.lower(), marker
        assert marker.decode().encode("utf-16-le").lower() not in binary.lower(), marker
    for path in release_files(ROOT / "client"):
        assert "testboot" not in str(path).lower()
        assert path.suffix.lower() not in {".log", ".cfg", ".key", ".secret"}
    print(f"{len(ids)} emotes, {len(music_names())} songs ok")


def archive(name, entries):
    destination = DIST / name
    names = set()
    with zipfile.ZipFile(
        destination, "w", zipfile.ZIP_DEFLATED, compresslevel=9
    ) as output:
        for path, relative in entries:
            relative = str(relative).replace("\\", "/")
            assert relative not in names, f"Duplicate archive path: {relative}"
            assert not relative.startswith("/") and ".." not in relative.split("/")
            assert path.name not in {"room.key", ".env", "local-config.json"}
            assert not relative.endswith((".log", ".pyc", ".secret"))
            names.add(relative)
            # fixed metadata keeps identical inputs reproducible.
            info = zipfile.ZipInfo(relative, (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            output.writestr(info, path.read_bytes(), compresslevel=9)
    with zipfile.ZipFile(destination) as output:
        assert output.testzip() is None
    destination.with_suffix(destination.suffix + ".sha256").write_text(
        f"{digest(destination)}  {destination.name}\n", encoding="ascii"
    )
    print(f"{destination.name}: {destination.stat().st_size / 1024**2:.1f} MiB")


def main():
    if "--checksums" in sys.argv:
        write_checksums()
        return
    validate()
    DIST.mkdir(exist_ok=True)
    public_docs = [
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "THIRD_PARTY_NOTICES.md",
        "SECURITY.md",
        "manifest.json",
        "icon.png",
    ]
    client = [(ROOT / name, name) for name in public_docs]
    client.extend(
        (path, path.relative_to(ROOT / "client"))
        for path in release_files(ROOT / "client")
    )
    client.append((ROOT / "build/ceaikaemotes.dll", "plugins/ceaikaemotes.dll"))
    client.extend(
        (path, "plugins/ceaikaemotes/" + path.name) for path in release_files(MUSIC)
    )
    archive(f"ceaikaemotes-{VERSION}-client.zip", client)
    # same layout works for manual installs and Thunderstore.
    thunderstore = DIST / f"ceaikaemotes-{VERSION}-thunderstore.zip"
    shutil.copyfile(DIST / f"ceaikaemotes-{VERSION}-client.zip", thunderstore)
    thunderstore.with_suffix(".zip.sha256").write_text(
        f"{digest(thunderstore)}  {thunderstore.name}\n", encoding="ascii"
    )

    source = [
        (ROOT / name, "ceaikaemotes/" + name)
        for name in public_docs + [".gitignore", ".gitattributes", ".clang-format"]
    ]
    for folder in ["client", "native", "assets", "relay", "tools", "docs", "artwork"]:
        source.extend(
            (path, "ceaikaemotes/" + path.relative_to(ROOT).as_posix())
            for path in release_files(ROOT / folder)
        )
    archive(f"ceaikaemotes-{VERSION}-source.zip", source)

    update = [(path, "relay/" + path.name) for path in release_files(ROOT / "relay")]
    update.extend((ROOT / name, name) for name in ["LICENSE", "SECURITY.md"])
    update.append((ROOT / "docs/hosting.md", "README.md"))
    archive(f"ceaikaemotes-{VERSION}-relay.zip", update)


if __name__ == "__main__":
    main()
