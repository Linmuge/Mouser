import tempfile
from pathlib import Path
from types import SimpleNamespace
import unittest

from tools.generate_update_manifest import build_payload


class GenerateUpdateManifestTests(unittest.TestCase):
    def test_universal_macos_dmg_is_published_for_both_architectures(self):
        with tempfile.TemporaryDirectory() as directory:
            asset_dir = Path(directory)
            dmg = asset_dir / "Mouser-3.8.0.dmg"
            dmg.write_bytes(b"native universal dmg")
            (asset_dir / "Mouser-3.8.0-debug.dmg").write_bytes(b"debug dmg")
            args = SimpleNamespace(
                asset_dir=str(asset_dir),
                tag="v3.8.0",
                repo="Linmuge/Mouser",
                expires_days="30",
                build_number="",
                commit="abc123",
            )

            payload = build_payload(args)

            arm = payload["assets"]["macos-arm64"]
            intel = payload["assets"]["macos-x86_64"]
            self.assertEqual(arm["name"], "Mouser-3.8.0.dmg")
            self.assertEqual(intel, arm)
            self.assertNotIn("debug", arm["name"])


if __name__ == "__main__":
    unittest.main()
