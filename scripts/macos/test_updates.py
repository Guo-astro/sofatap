import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from sparkle import inventory


class UpdatePackagingTests(unittest.TestCase):
    def test_framework_symlinks_are_inventoried_without_following_twice(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / 'Versions/B/Sparkle'
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'framework fixture')
            (root / 'Versions/Current').symlink_to('B')
            (root / 'Sparkle').symlink_to('Versions/Current/Sparkle')
            data = inventory(root)
            self.assertEqual(data['Sparkle'], {'symlink': 'Versions/Current/Sparkle'})
            self.assertIn('Versions/B/Sparkle', data)
            self.assertNotIn('Versions/Current/Sparkle', data)
            binary.write_bytes(b'tampered')
            self.assertNotEqual(data['Versions/B/Sparkle'], inventory(root)['Versions/B/Sparkle'])

    def test_escaping_symlink_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            framework = root / 'Sparkle.framework'
            framework.mkdir()
            (root / 'outside').write_text('other code')
            (framework / 'Sparkle').symlink_to('../outside')
            with self.assertRaises(ValueError):
                inventory(framework)

    def test_dangling_symlink_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'Sparkle').symlink_to('absent')
            with self.assertRaises(ValueError):
                inventory(root)

    def test_feed_generation_rejects_archive_without_notarization_before_keychain_or_network(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / 'SofaTap-macOS-arm64-notarized.zip'
            archive.write_bytes(b'not a release')
            receipt = root / 'receipt.json'
            receipt.write_text(json.dumps({'stage': 'prepared', 'notarized': False}))
            result = subprocess.run([sys.executable, str(Path(__file__).with_name('generate-appcast.py')),
                '--archive', str(archive), '--receipt', str(receipt), '--architecture', 'arm64',
                '--tag', 'v0.8.0-beta.1', '--output-dir', str(root / 'output')], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('completed notarization', result.stderr)
            self.assertFalse((root / 'output').exists())


if __name__ == '__main__':
    unittest.main()
