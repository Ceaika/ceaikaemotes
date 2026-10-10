"""Give a Titanfall v53 pilot a private name and the catalog's animation includes.

Only the header and appended strings/include table change. Geometry, materials,
bones, and the embedded vertex/physics data keep their original offsets.
Layout reference: ZeqMacaw/Crowbar, SourceModel53/SourceMdlFile53.vb.
"""

import argparse
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


def prepare_model(data, name, animation_models):
    includes = read_includes(data)
    encoded_name = name.encode("ascii")
    if (
        not name.startswith("ceaikaemotes/pilots/")
        or not name.endswith(".mdl")
        or ".." in name
        or "\\" in name
        or "\0" in name
        or len(encoded_name) >= 64
    ):
        raise ValueError("Expected a private ceaikaemotes pilot name under 64 bytes")
    existing = {path for _, path in includes}
    for path in animation_models:
        if path not in existing:
            includes.append(("", path))
            existing.add(path)

    result = bytearray(data)
    result.extend(b"\0" * (-len(result) % 4))
    table = len(result)
    result.extend(b"\0" * (len(includes) * 8))
    for i, (label, path) in enumerate(includes):
        entry = table + i * 8
        label_offset = 0
        if label:
            label_offset = len(result) - entry
            result.extend(label.encode("ascii") + b"\0")
        name_offset = len(result) - entry
        result.extend(path.encode("ascii") + b"\0")
        struct.pack_into("<ii", result, entry, label_offset, name_offset)
    struct.pack_into("<ii", result, 0x154, len(includes), table)
    struct.pack_into("<i", result, 0x0C, len(result))
    result.extend(encoded_name + b"\0")
    result[0x10:0x50] = encoded_name.ljust(64, b"\0")
    struct.pack_into("<i", result, 0x50, len(result))
    return bytes(result)


def validate_models(root=ROOT):
    """Check the model assets used by the client before packaging a release."""
    content = root / "client/mods/ceaikaemotes/mod"
    models = content / "models"
    assert not list((models / "humans/pilots").glob("*.mdl")), (
        "Normal pilot overrides conflict with cosmetic mods"
    )
    script = (content / "scripts/vscripts/cl_ceaikaemotes_models.nut").read_text()
    selected = set(
        re.findall(r'\$"(models/ceaikaemotes/pilots/[^"\n]+\.mdl)"', script)
    )
    supplied = {
        path.relative_to(content).as_posix()
        for path in (models / "ceaikaemotes/pilots").glob("*.mdl")
    }
    assert selected == supplied and len(supplied) == 16, (
        "Dancing model mappings do not match the supplied assets"
    )
    animations = {
        entry["animation_model"]
        for entry in json.loads((root / "assets/catalog.json").read_text())
    }
    for relative in supplied:
        data = (content / relative).read_bytes()
        includes = {path for _, path in read_includes(data)}
        assert animations.issubset(includes), f"Missing emote libraries: {relative}"
        name = relative.removeprefix("models/")
        assert read_string(data, 0x10) == name, f"Wrong model header name: {relative}"
        name_copy = struct.unpack_from("<i", data, 0x0C)[0]
        assert read_string(data, name_copy) == name, f"Wrong model name copy: {relative}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Extracted v53 pilot MDL")
    parser.add_argument("destination", type=Path)
    parser.add_argument("--name", required=True, help="Internal path, without models/")
    args = parser.parse_args()
    catalog = json.loads((ROOT / "assets/catalog.json").read_text())
    result = prepare_model(
        args.source.read_bytes(),
        args.name,
        [entry["animation_model"] for entry in catalog],
    )
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    args.destination.write_bytes(result)


if __name__ == "__main__":
    main()
