"""Validate the stock-path models and pristine native-plugin defaults."""

import json
from pathlib import Path
import re
import struct


ROOT = Path(__file__).resolve().parents[1]


def read_string(data, offset):
    if not 0 < offset < len(data):
        raise ValueError("Model string offset is outside the file")
    try:
        return data[offset : data.index(0, offset)].decode("ascii")
    except (ValueError, UnicodeDecodeError) as error:
        raise ValueError("Invalid model string") from error


def read_includes(data):
    if len(data) < 0x1D8 or data[:8] != b"IDST\x35\0\0\0":
        raise ValueError("Expected a Titanfall v53 MDL")
    if struct.unpack_from("<i", data, 0x50)[0] != len(data):
        raise ValueError("Model length does not match its header")
    count, offset = struct.unpack_from("<ii", data, 0x154)
    if count < 0 or offset < 0 or offset + count * 8 > len(data):
        raise ValueError("Model include table is outside the file")
    includes = []
    for i in range(count):
        entry = offset + i * 8
        label, name = struct.unpack_from("<ii", data, entry)
        includes.append(
            (
                read_string(data, entry + label) if label else "",
                read_string(data, entry + name),
            )
        )
    return includes



def validate_models(root=ROOT):
    mod = root / "client/mods/ceaikaemotes"
    content = mod / "mod"
    models = content / "models"
    supplied = {path.name for path in (models / "humans/pilots").glob("*.mdl")}
    assert len(supplied) == 14, "Keep the stock pilot paths required for model indices"
    assert not list((models / "ceaikaemotes/pilots").glob("*.mdl")), (
        "Private aliases cannot reliably obtain model indices on stock servers"
    )
    defaults = {path.name for path in (mod / "pilot-defaults").glob("*.mdl")}
    assert defaults == {
        f"pilot_medium_{kind}_{sex}.mdl"
        for kind in ["geist", "reaper"] for sex in ["f", "m"]
    }
    script = (content / "scripts/vscripts/cl_ceaikaemotes_models.nut").read_text()
    selected = set(re.findall(r'\$"models/humans/pilots/([^"\n]+\.mdl)"', script))
    assert selected == supplied, "Stock pilot mappings do not match the supplied assets"
    animations = {
        entry["animation_model"]
        for entry in json.loads((root / "assets/catalog.json").read_text())
    }
    native = (root / "native/emote_models.h").read_text()
    assert set(re.findall(r'"(models/emotes/[^"\n]+\.mdl)"', native)) == animations
    for name in supplied:
        # Installation copies can contain a local cosmetic. Validate the pristine
        # source that the packager actually places in the release archive.
        path = mod / "pilot-defaults" / name if name in defaults else models / "humans/pilots" / name
        data = path.read_bytes()
        includes = {path for _, path in read_includes(data)}
        assert animations.issubset(includes), f"Missing emote libraries: {name}"
        assert read_string(data, 0x10) == "humans/pilots/" + name


if __name__ == "__main__":
    validate_models()
