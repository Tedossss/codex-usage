import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

from codex_usage.cli import main
from tests.test_reader import event


class CLITests(unittest.TestCase):
    def test_json_status(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sessions = root / "sessions"
            sessions.mkdir()
            (sessions / "session.jsonl").write_text(json.dumps(event()) + "\n", encoding="utf-8")
            output = io.StringIO()
            with patch("codex_usage.cli.count_live_codex_processes", return_value=2):
                with redirect_stdout(output):
                    code = main(["--codex-home", str(root), "status", "--json"])

            self.assertEqual(code, 0)
            parsed = json.loads(output.getvalue())
            self.assertEqual(parsed["primary"]["used_percent"], 17)
            self.assertEqual(parsed["live_processes"], 2)

    def test_missing_data_has_clear_error(self):
        with tempfile.TemporaryDirectory() as directory:
            error = io.StringIO()
            with redirect_stderr(error):
                code = main(["--codex-home", directory, "status"])
            self.assertEqual(code, 1)
            self.assertIn("no token_count events", error.getvalue())


if __name__ == "__main__":
    unittest.main()
