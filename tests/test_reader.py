import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from codex_usage.autostart import desktop_entry
from codex_usage.formatting import bar, reset_text
from codex_usage.reader import (
    classify_codex_process,
    latest_snapshot,
    parse_token_count_event,
    reverse_lines,
)


def event(timestamp="2026-08-07T12:00:00Z", primary=17.0, secondary=42.0):
    return {
        "timestamp": timestamp,
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "info": {
                "total_token_usage": {
                    "input_tokens": 1200,
                    "cached_input_tokens": 800,
                    "output_tokens": 300,
                    "reasoning_output_tokens": 100,
                    "total_tokens": 1500,
                }
            },
            "rate_limits": {
                "primary": {
                    "used_percent": primary,
                    "window_minutes": 300,
                    "resets_at": 1786111200,
                },
                "secondary": {
                    "used_percent": secondary,
                    "window_minutes": 10080,
                    "resets_at": 1786716000,
                },
                "plan_type": "plus",
                "credits": None,
            },
        },
    }


class ReaderTests(unittest.TestCase):
    def test_parses_codex_token_count_shape(self):
        snapshot = parse_token_count_event(json.dumps(event()), "fixture.jsonl")

        self.assertIsNotNone(snapshot)
        self.assertEqual(snapshot.primary.used_percent, 17)
        self.assertEqual(snapshot.primary.label, "5-hour window")
        self.assertEqual(snapshot.secondary.label, "7-day window")
        self.assertEqual(snapshot.plan_type, "plus")
        self.assertEqual(snapshot.tokens.total_tokens, 1500)

    def test_accepts_rate_limits_without_token_info(self):
        value = event()
        value["payload"]["info"] = None
        snapshot = parse_token_count_event(json.dumps(value))

        self.assertIsNotNone(snapshot)
        self.assertIsNone(snapshot.tokens)

    def test_window_labels_follow_duration_not_field_name(self):
        value = event()
        value["payload"]["rate_limits"]["primary"]["window_minutes"] = 10_080
        value["payload"]["rate_limits"]["secondary"] = None
        snapshot = parse_token_count_event(json.dumps(value))

        self.assertEqual(snapshot.primary.label, "7-day window")
        self.assertIsNone(snapshot.secondary)

    def test_ignores_unrelated_and_malformed_events(self):
        self.assertIsNone(parse_token_count_event("not-json"))
        self.assertIsNone(parse_token_count_event(json.dumps({"type": "event_msg", "payload": {}})))

    def test_clamps_percentage(self):
        snapshot = parse_token_count_event(json.dumps(event(primary=140, secondary=-2)))
        self.assertEqual(snapshot.primary.used_percent, 100)
        self.assertEqual(snapshot.secondary.used_percent, 0)

    def test_reverse_lines_handles_missing_final_newline_and_unicode(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "events.jsonl"
            path.write_text("one\ntwø\nthree", encoding="utf-8")
            self.assertEqual(list(reverse_lines(path, block_size=4)), ["three", "twø", "one"])

    def test_latest_snapshot_compares_events_across_active_and_archived(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            active = root / "sessions" / "2026" / "08"
            archived = root / "archived_sessions"
            active.mkdir(parents=True)
            archived.mkdir()
            (active / "old.jsonl").write_text(
                json.dumps(event("2026-08-07T11:00:00Z", primary=10)) + "\n",
                encoding="utf-8",
            )
            (archived / "new.jsonl").write_text(
                "{}\n" + json.dumps(event("2026-08-07T13:00:00Z", primary=55)) + "\n",
                encoding="utf-8",
            )

            snapshot = latest_snapshot(root)

            self.assertEqual(snapshot.primary.used_percent, 55)
            self.assertTrue(snapshot.source.endswith("new.jsonl"))

    def test_formatting_is_stable(self):
        snapshot = parse_token_count_event(json.dumps(event()))
        self.assertEqual(bar(42), "████░░░░░░")
        self.assertIn(
            "in 1h 0m",
            reset_text(snapshot.primary, datetime(2026, 8, 7, 13, 0, tzinfo=timezone.utc)),
        )

    def test_autostart_uses_absolute_runtime_paths(self):
        entry = desktop_entry()
        self.assertIn('Exec="/', entry)
        self.assertIn('run.py" tray', entry)
        self.assertNotIn("/usr/bin/env codex-usage", entry)
        self.assertIn("Categories=Utility;", entry)

    def test_classifies_native_codex_and_launchers_but_not_helpers(self):
        native = "/usr/lib/node_modules/@openai/codex/vendor/bin/codex"
        self.assertEqual(classify_codex_process(native, [native]), "native")
        self.assertEqual(
            classify_codex_process("/usr/bin/node", ["node", "/usr/bin/codex"]),
            "launcher",
        )
        self.assertEqual(
            classify_codex_process(
                "/usr/bin/bwrap",
                ["bwrap", "--argv0", "codex-linux-sandbox", "--", native],
            ),
            "launcher",
        )
        self.assertIsNone(
            classify_codex_process(
                "/usr/lib/node_modules/@openai/codex/vendor/bin/codex-code-mode-host",
                ["codex-code-mode-host"],
            )
        )


if __name__ == "__main__":
    unittest.main()
