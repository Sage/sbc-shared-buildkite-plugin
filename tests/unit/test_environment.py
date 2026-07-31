import io
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))

from sbc_shared.environment import (
    PluginEnvironment,
    build_environment,
    write_shell_environment,
)


class EnvironmentTest(unittest.TestCase):
    def test_build_environment_uses_merge_queue_branch_basename(self):
        with tempfile.TemporaryDirectory() as directory:
            application_file = Path(directory) / ".application"
            application_file.write_text("myapp\n", encoding="utf-8")
            value = build_environment(
                {
                    "BUILDKITE_PLUGIN_SBC_SHARED_REPO_PREFIX": "product",
                    "BUILDKITE_BRANCH": "gh-readonly-queue/main/pr-1-sha",
                    "BUILDKITE_COMMIT": "abc123",
                    "AWS_REGION": "eu-west-1",
                    "BUILDKITE": "true",
                },
                application_file,
                datetime(2026, 7, 31, 12, 30, 0),
            )

        self.assertEqual(value.branch, "pr-1-sha")
        self.assertEqual(value.repository, "product/myapp")
        self.assertEqual(value.buildkit_progress, "plain")

    def test_shell_output_quotes_values_and_unsets_blank_options(self):
        with tempfile.TemporaryDirectory() as directory:
            application_file = Path(directory) / ".application"
            application_file.write_text("my app\n", encoding="utf-8")
            build = build_environment(
                {
                    "BUILDKITE_BRANCH": "main",
                    "BUILDKITE_COMMIT": "abc123",
                    "AWS_REGION": "eu-west-1",
                },
                application_file,
                datetime(2026, 7, 31),
            )
        output = io.StringIO()
        write_shell_environment(output, build, PluginEnvironment.from_environ({}))

        self.assertIn("export APP='my app'", output.getvalue())
        self.assertIn("unset ENVIRONMENT", output.getvalue())

    def test_empty_plugin_coverage_uses_existing_coverage(self):
        plugin = PluginEnvironment.from_environ(
            {
                "BUILDKITE_PLUGIN_SBC_SHARED_COVERAGE": "",
                "COVERAGE": "87.5",
            }
        )

        self.assertEqual(plugin.values["COVERAGE"], "87.5")


if __name__ == "__main__":
    unittest.main()
