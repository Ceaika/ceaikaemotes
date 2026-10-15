"""Checks for stock model paths and release assets used by native preparation."""

import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from emote_models import read_includes, validate_models
import package


ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "client/mods/ceaikaemotes"


class ModelCompatibilityTests(unittest.TestCase):
    def test_stock_pilot_models_include_every_dance(self):
        catalog = json.loads((ROOT / "assets/catalog.json").read_text())
        animations = {entry["animation_model"] for entry in catalog}
        paths = list((MOD / "mod/models/humans/pilots").glob("*.mdl"))
        self.assertEqual(len(paths), 14)
        for path in paths:
            with self.subTest(model=path.name):
                includes = {name for _, name in read_includes(path.read_bytes())}
                self.assertTrue(animations.issubset(includes), animations - includes)

    def test_pristine_defaults_can_restore_each_cat_ears_pilot(self):
        defaults = sorted((MOD / "pilot-defaults").glob("*.mdl"))
        self.assertEqual(
            {path.name for path in defaults},
            {
                "pilot_medium_geist_f.mdl", "pilot_medium_geist_m.mdl",
                "pilot_medium_reaper_f.mdl", "pilot_medium_reaper_m.mdl",
            },
        )
        for path in defaults:
            with self.subTest(model=path.name):
                self.assertEqual(
                    path.read_bytes(),
                    (MOD / "mod/models/humans/pilots" / path.name).read_bytes(),
                )

    def test_release_model_validation_accepts_the_shipped_assets(self):
        validate_models(ROOT)

    def test_packaging_replaces_generated_cat_ears_with_pristine_defaults(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            mod = root / "client/mods/ceaikaemotes"
            generated = mod / "mod/models/humans/pilots/pilot_medium_geist_f.mdl"
            default = mod / "pilot-defaults/pilot_medium_geist_f.mdl"
            generated.parent.mkdir(parents=True)
            default.parent.mkdir(parents=True)
            generated.write_bytes(b"installed Cat Ears mesh")
            default.write_bytes(b"shipped stock pilot")
            with patch.object(package, "ROOT", root), patch.object(package, "DIST", root):
                package.archive("models.zip", [(generated, "pilot.mdl")])
            with zipfile.ZipFile(root / "models.zip") as archive:
                self.assertEqual(archive.read("pilot.mdl"), b"shipped stock pilot")


if __name__ == "__main__":
    unittest.main()
