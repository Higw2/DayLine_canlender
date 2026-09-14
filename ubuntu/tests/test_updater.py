import hashlib
import io
from pathlib import Path
import shutil
import tarfile
import tempfile
import unittest

from dayline.updater import ASSET_NAME, AvailableUpdate, download_and_stage, parse_version, select_update


def release(tag, *, name=None, asset=True, draft=False, prerelease=False):
    assets = [{
        "name": ASSET_NAME,
        "size": 1024,
        "digest": "sha256:" + "a" * 64,
        "browser_download_url": f"https://github.com/example/{tag}/{ASSET_NAME}",
    }] if asset else [{"name": "DayLine-macOS.zip", "size": 1024}]
    return {
        "tag_name": tag,
        "name": name,
        "body": "更新内容",
        "html_url": f"https://github.com/example/releases/tag/{tag}",
        "draft": draft,
        "prerelease": prerelease,
        "assets": assets,
    }


class UpdaterTests(unittest.TestCase):
    def test_selects_newest_published_ubuntu_release(self):
        found = select_update([
            release("v1.10.0"), release("v1.2.0"), release("Macos_version", name="Macos version 1.0", asset=False),
            release("v2.0.0", draft=True), release("v1.11.0", prerelease=True),
        ], "1.0.0")
        self.assertEqual(found.version, "1.10.0")
        self.assertEqual(found.tag, "v1.10.0")
        self.assertEqual(parse_version("v1.2.3"), (1, 2, 3))
        self.assertIsNone(select_update([release("v1.0.0")], "1.0.0"))

    def test_download_verifies_digest_and_embedded_version(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / ASSET_NAME
            with tarfile.open(archive, "w:gz") as bundle:
                for name, content in {
                    "DayLine-Ubuntu-24.04/VERSION": b"1.2.0\n",
                    "DayLine-Ubuntu-24.04/install.py": b"print('install')\n",
                    "DayLine-Ubuntu-24.04/update_helper.py": b"print('helper')\n",
                }.items():
                    info = tarfile.TarInfo(name)
                    info.size = len(content)
                    bundle.addfile(info, io.BytesIO(content))
            content = archive.read_bytes()
            update = AvailableUpdate("1.2.0", "v1.2.0", "v1.2.0", "", "", archive.as_uri(), len(content), hashlib.sha256(content).hexdigest())
            package = download_and_stage(update)
            try:
                self.assertEqual((package / "VERSION").read_text().strip(), "1.2.0")
            finally:
                shutil.rmtree(package.parent)
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                download_and_stage(AvailableUpdate("1.2.0", "v1.2.0", "v1.2.0", "", "", archive.as_uri(), len(content), "0" * 64))


if __name__ == "__main__":
    unittest.main()
