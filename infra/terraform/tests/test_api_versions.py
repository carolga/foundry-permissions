import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA_PLANE_BLOCK = re.compile(
    r'^resource\s+"azapi_data_plane_resource"\s+"[^"]+"\s*\{.*?^\}',
    re.MULTILINE | re.DOTALL,
)
ARM_TYPE = re.compile(r'^\s*type\s*=\s*"(Microsoft\.[^"]+)"', re.MULTILINE)
STABLE_VERSION = re.compile(r"^\d{4}-\d{2}-\d{2}$")


class ArmApiVersionTests(unittest.TestCase):
    def test_all_terraform_arm_types_use_static_stable_versions(self):
        types = []
        for path in ROOT.rglob("*.tf"):
            if ".terraform" in path.parts:
                continue
            content = path.read_text(encoding="utf-8")
            data_plane_blocks = list(DATA_PLANE_BLOCK.finditer(content))
            for match in ARM_TYPE.finditer(content):
                if any(block.start() <= match.start() < block.end() for block in data_plane_blocks):
                    self.assertEqual(match.group(1), "Microsoft.Foundry/agents@v1")
                else:
                    types.append((path.relative_to(ROOT), match.group(1)))

        self.assertTrue(types, "No ARM resource types found")
        for path, resource_type in types:
            with self.subTest(path=path, resource_type=resource_type):
                _, separator, version = resource_type.rpartition("@")
                self.assertTrue(
                    separator and STABLE_VERSION.fullmatch(version),
                    f"{path}: {resource_type} does not use a static stable API version",
                )


if __name__ == "__main__":
    unittest.main()
