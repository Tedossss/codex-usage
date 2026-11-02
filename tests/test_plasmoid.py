import json
import unittest
from pathlib import Path

from codex_usage.reader import parse_token_count_event
from tests.test_reader import event


class PlasmoidPackageTests(unittest.TestCase):
    root = Path(__file__).parents[1] / "plasmoid"

    def test_metadata_declares_plasma_applet(self):
        metadata = json.loads((self.root / "metadata.json").read_text(encoding="utf-8"))
        self.assertEqual(metadata["KPackageStructure"], "Plasma/Applet")
        self.assertEqual(metadata["KPlugin"]["Id"], "com.nfalach.codexusage")
        self.assertEqual(metadata["X-Plasma-API-Minimum-Version"], "6.0")

    def test_qml_uses_existing_json_cli(self):
        qml = (self.root / "contents/ui/main.qml").read_text(encoding="utf-8")
        self.assertIn("codex-usage", qml)
        self.assertIn("status --json", qml)
        self.assertIn('engine: "executable"', qml)

    def test_qml_matches_json_timestamp_contract(self):
        snapshot = parse_token_count_event(json.dumps(event()))
        payload = snapshot.to_dict()
        self.assertIsInstance(payload["captured_at"], str)
        self.assertIsInstance(payload["primary"]["resets_at"], str)

        qml = (self.root / "contents/ui/main.qml").read_text(encoding="utf-8")
        self.assertIn("new Date(resetValue)", qml)
        self.assertIn("capturedAt = parsed.captured_at", qml)
        self.assertIn("trackedWindow()", qml)

    def test_widget_uses_remaining_usage_and_has_separate_settings(self):
        qml = (self.root / "contents/ui/main.qml").read_text(encoding="utf-8")
        self.assertIn("100 - window.used_percent", qml)
        self.assertIn("remainingPercent", qml)
        self.assertIn("plasmoid.configuration.refreshInterval", qml)
        self.assertTrue((self.root / "contents/config/config.qml").is_file())
        self.assertTrue((self.root / "contents/ui/config/ConfigGeneral.qml").is_file())

        config_model = (self.root / "contents/config/config.qml").read_text(encoding="utf-8")
        self.assertIn('source: "config/ConfigGeneral.qml"', config_model)


if __name__ == "__main__":
    unittest.main()
