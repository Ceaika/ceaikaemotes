"""Regression checks for the shipped emote models and cosmetic coexistence."""

import json
from pathlib import Path
import struct
import unittest

from emote_models import prepare_model, read_includes, validate_models


ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "client/mods/ceaikaemotes/mod/models"
PILOTS = MODELS / "ceaikaemotes/pilots"


def cstring(data, offset):
    return data[offset : data.index(0, offset)].decode("ascii")


class ModelCompatibilityTests(unittest.TestCase):
    def test_normal_pilot_paths_are_left_to_the_game_and_cosmetic_mods(self):
        self.assertEqual(list((MODELS / "humans/pilots").glob("*.mdl")), [])

    def test_every_pilot_has_a_private_dancing_model(self):
        expected = {
            f"pilot_{kind}_{sex}.mdl"
            for kind in [
                "heavy_drex",
                "heavy_roog",
                "light_ged",
                "light_jester",
                "medium_geist",
                "medium_reaper",
                "medium_stalker",
            ]
            for sex in ["f", "m"]
        }
        self.assertEqual({p.name for p in PILOTS.glob("pilot_*.mdl")}, expected)

    def test_private_models_keep_all_emotes_and_their_own_internal_names(self):
        catalog = json.loads((ROOT / "assets/catalog.json").read_text())
        animations = {entry["animation_model"] for entry in catalog}
        paths = list(PILOTS.glob("*.mdl"))
        self.assertEqual(len(paths), 16)  # 14 standard pilots + two Cat Ears meshes.
        for path in paths:
            with self.subTest(model=path.name):
                data = path.read_bytes()
                self.assertEqual(data[:8], b"IDST\x35\0\0\0")
                self.assertEqual(struct.unpack_from("<i", data, 0x50)[0], len(data))
                name = path.relative_to(MODELS).as_posix()
                self.assertEqual(cstring(data, 0x10), name)
                self.assertEqual(
                    cstring(data, struct.unpack_from("<i", data, 0x0C)[0]), name
                )
                count, offset = struct.unpack_from("<ii", data, 0x154)
                includes = {
                    cstring(
                        data,
                        offset + i * 8
                        + struct.unpack_from("<i", data, offset + i * 8 + 4)[0],
                    )
                    for i in range(count)
                }
                self.assertTrue(animations.issubset(includes), animations - includes)


def pilot_fixture():
    """Small v53 layout with a labelled include and a distinctive model payload."""
    data = bytearray(512)
    data[:8] = b"IDST\x35\0\0\0"
    name = b"humans/pilots/pilot_medium_reaper_f.mdl\0"
    data[0x10 : 0x10 + len(name)] = name
    struct.pack_into("<i", data, 0x0C, len(data))
    data.extend(name)
    label = len(data)
    data.extend(b"shared\0")
    path = len(data)
    data.extend(b"models/humans/pete/pilot_shared.mdl\0")
    struct.pack_into("<ii", data, 0x154, 1, 0x1D8)
    struct.pack_into("<ii", data, 0x1D8, label - 0x1D8, path - 0x1D8)
    data.extend(b"MODEL_PAYLOAD\xff\x80\x01")
    struct.pack_into("<i", data, 0x50, len(data))
    return bytes(data)


class ModelPreparationTests(unittest.TestCase):
    def test_geometry_and_existing_include_labels_survive_preparation(self):
        source = pilot_fixture()
        result = prepare_model(
            source, "ceaikaemotes/pilots/cat_ears_f.mdl",
            ["models/emotes/emote_oj/anim.mdl"],
        )
        self.assertEqual(result[:0x0C], source[:0x0C])
        self.assertEqual(result[0x54:0x154], source[0x54:0x154])
        self.assertEqual(result[0x15C : len(source)], source[0x15C:])
        self.assertEqual(
            read_includes(result),
            [
                ("shared", "models/humans/pete/pilot_shared.mdl"),
                ("", "models/emotes/emote_oj/anim.mdl"),
            ],
        )
        self.assertEqual(cstring(result, 0x10), "ceaikaemotes/pilots/cat_ears_f.mdl")
        self.assertEqual(
            cstring(result, struct.unpack_from("<i", result, 0x0C)[0]),
            "ceaikaemotes/pilots/cat_ears_f.mdl",
        )

    def test_existing_and_repeated_animations_are_not_duplicated(self):
        result = prepare_model(
            pilot_fixture(), "ceaikaemotes/pilots/cat_ears_f.mdl",
            [
                "models/humans/pete/pilot_shared.mdl",
                "models/emotes/emote_oj/anim.mdl",
                "models/emotes/emote_oj/anim.mdl",
            ],
        )
        self.assertEqual(len(read_includes(result)), 2)

    def test_invalid_models_are_rejected_before_transformation(self):
        for offset, value in [(4, 49), (0x50, 12), (0x154, -1), (0x158, 999999)]:
            with self.subTest(offset=offset):
                source = bytearray(pilot_fixture())
                struct.pack_into("<i", source, offset, value)
                with self.assertRaises(ValueError):
                    prepare_model(source, "ceaikaemotes/pilots/cat_ears_f.mdl", [])

    def test_normal_or_unusable_model_names_are_rejected(self):
        for name in [
            "humans/pilots/pilot_medium_reaper_f.mdl",
            "ceaikaemotes/pilots/../cat.mdl",
            "ceaikaemotes/pilots/cat\0.mdl",
            "ceaikaemotes/pilots/" + "x" * 60 + ".mdl",
        ]:
            with self.subTest(name=name), self.assertRaises(ValueError):
                prepare_model(pilot_fixture(), name, [])

    def test_release_model_validation_accepts_the_shipped_assets(self):
        validate_models(ROOT)


if __name__ == "__main__":
    unittest.main()
