import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))

from sbc_shared.actions import ImageConfig, image_push


class ImagePushTest(unittest.TestCase):
    def config(self, **changes):
        values = {
            "account_id": "123",
            "application": "myapp",
            "variant": "application",
            "multiarch": False,
            "build_number": "42",
            "region": "eu-west-1",
            "repository": "sageone/myapp",
            "build_ecr": "build.example/sageone/buildkite",
        }
        values.update(changes)
        return ImageConfig(**values)

    def test_plans_single_arch_manifest(self):
        push = image_push(self.config(), "feature")

        self.assertEqual(
            push.target,
            "123.dkr.ecr.eu-west-1.amazonaws.com/sageone/myapp:feature",
        )
        self.assertEqual(
            push.sources,
            ("build.example/sageone/buildkite:myapp-application-build-42",),
        )

    def test_plans_multiarch_manifest_with_target_override(self):
        push = image_push(
            self.config(multiarch=True, target_tag="last-successful-build"),
            "ignored-branch",
        )

        self.assertTrue(push.target.endswith(":last-successful-build"))
        self.assertEqual(len(push.sources), 2)
        self.assertIn("myapp-application-arm64-build-42", push.sources[1])


if __name__ == "__main__":
    unittest.main()
