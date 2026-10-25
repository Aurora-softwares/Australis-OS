"""Guard automatic CI discovery, de-duplication and sharding."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.run_ci_tests import parse_targets, select_shard


class CiDiscoveryTests(unittest.TestCase):
    def test_reads_only_explicit_ci_targets(self):
        database = (
            ".PHONY: test-ci-storage test-ci-display\n"
            "test-ci-storage: test-storage\n"
            "test-ci-display: test-display\n"
            "test-ci-storage: test-storage\n"
            "test-ci-%: test-%\n"
            "test-storage: check-build-tools\n"
            "other-test-ci-false: other\n"
        )
        self.assertEqual(parse_targets(database), [
            "test-ci-display", "test-ci-storage",
        ])

    def test_shards_cover_every_target_once(self):
        targets = [f"test-ci-check-{number:02}" for number in range(17)]
        pieces = [select_shard(targets, index, 4) for index in range(4)]
        self.assertEqual(sorted(target for piece in pieces for target in piece), targets)

    def test_empty_registry_and_invalid_shard_are_not_silent_success(self):
        self.assertEqual(parse_targets("test-not-ci: test\n"), [])
        with self.assertRaises(ValueError):
            select_shard(["test-ci-a"], 2, 2)


if __name__ == "__main__":
    unittest.main()
