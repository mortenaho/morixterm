import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from next_release_version import next_release_tag


class NextReleaseVersionTests(unittest.TestCase):
    def test_first_major_release_is_v3(self):
        self.assertEqual(next_release_tag([]), "v3")

    def test_increments_latest_major_tag(self):
        self.assertEqual(next_release_tag(["v3", "v4", "v2"]), "v5")

    def test_ignores_old_semver_and_build_tags(self):
        self.assertEqual(next_release_tag(["v3", "v2.0.4", "v0.1.0-build.54"]), "v4")

    def test_ignores_invalid_and_leading_zero_tags(self):
        self.assertEqual(next_release_tag(["v3", "v04", "v0", "v5-beta", "x9"]), "v4")


if __name__ == "__main__":
    unittest.main()
