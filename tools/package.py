"""Validate the release inputs and build client, source and relay archives."""

import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import wave
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
VERSION = json.loads((ROOT / "manifest.json").read_text())["version_number"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def release_files(folder):
    for path in sorted(folder.rglob("*")):
        if path.is_file() and "__pycache__" not in path.parts:
            yield path


def validate():
    manifest = json.loads((ROOT / "manifest.json").read_text())
    mod = json.loads((ROOT / "client/mods/ceaikaemotes/mod.json").read_text())
    assert mod["Version"] == VERSION
    assert re.fullmatch(r"\d+\.\d+\.\d+", VERSION)
    assert len(manifest["description"]) <= 250
    assert manifest["website_url"] == "https://github.com/Ceaika/ceaikaemotes"
    convars = {item["Name"]: item["DefaultValue"] for item in mod["ConVars"]}
    assert re.fullmatch(r"[a-zA-Z0-9_-]{24,128}", convars["emkey"])
    assert convars["em_enabled"] == "1"
    assert convars["em_auth_allowed_url"] == "", "Never ship someone else's approval"
    assert "auth-preview" not in convars["em_url"]
    assert not any(
        "auth_test" in item["Name"] or "binding_test" in item["Name"]
        for item in mod["ConCommands"]
    )
    archived = {
        item["Name"] for item in mod["ConVars"] if "ARCHIVE" in item.get("Flags", "")
    }
    assert "em_auth_allowed_url" in archived
    assert not {"em_auth_session", "em_auth_request"} & archived

    catalog = json.loads((ROOT / "assets/catalog.json").read_text())
    assert len(catalog) == 16
    assert {entry["track"] for entry in catalog} == set(range(16))
    assert {entry["id"] for entry in catalog if entry["traversal"]} == {
        "bbd_traversal",
        "griddy_traversal",
    }
    native_catalog = (ROOT / "native/emote_catalog.h").read_text()
    rates = [
        int(value)
        for value in re.search(
            r"TrackRates\[TrackCount\]\s*=\s*\{([^}]+)", native_catalog
        )
        .group(1)
        .split(",")
    ]
    scripts = ROOT / "client/mods/ceaikaemotes/mod/scripts/vscripts"
    script_catalog = (scripts / "sh_ceaikaemotes_catalog.nut").read_text()
    relay = (ROOT / "relay/relay.py").read_text()
    for entry in catalog:
        assert f'"{entry["id"]}"' in relay
        assert f'"{entry["id"]}"' in script_catalog
        assert f'"{entry["sequence"]}"' in script_catalog
        assert (
            ROOT / "client/mods/ceaikaemotes/mod" / entry["animation_model"]
        ).is_file()
        assert entry["native_file"] in native_catalog
        with wave.open(
            str(ROOT / "assets/music" / entry["native_file"]), "rb"
        ) as audio:
            assert audio.getnchannels() == 2 and audio.getsampwidth() == 2
            assert audio.getframerate() == rates[entry["track"]]
            assert audio.getnframes() > 0
    for line in (ROOT / "assets/checksums.sha256").read_text().splitlines():
        expected, relative = line.split("  ", 1)
        assert digest(ROOT / relative) == expected, f"Asset changed: {relative}"

    titans = json.loads((ROOT / "assets/titans.json").read_text())
    validation = json.loads((ROOT / "assets/titan-validation.json").read_text())[
        "models"
    ]
    assert len(titans) == len(validation) == 13
    for titan in titans:
        report = next(item for item in validation if item["id"] == titan["id"])
        assert report["clips"] == 16
        model_root = ROOT / "client/mods/ceaikaemotes/mod"
        assert digest(model_root / titan["path"]) == report["model_sha256"]
        library = model_root / "models/emotes/titans" / (titan["id"] + ".mdl")
        assert digest(library) == report["animation_sha256"]

    icon = (ROOT / "icon.png").read_bytes()
    assert icon[:8] == b"\x89PNG\r\n\x1a\n"
    assert struct.unpack(">II", icon[16:24]) == (256, 256)
    dll = ROOT / "build/ceaikaemotes.dll"
    assert dll.is_file() and dll.read_bytes()[:2] == b"MZ", "Build the DLL first"
    for path in release_files(ROOT / "client"):
        assert "testboot" not in str(path).lower()
        assert path.suffix.lower() not in {".log", ".cfg", ".key", ".secret"}


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
        (path, "plugins/ceaikaemotes/" + path.name)
        for path in sorted((ROOT / "assets/music").glob("*.wav"))
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
