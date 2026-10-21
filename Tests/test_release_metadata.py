# SPDX-License-Identifier: GPL-3.0-only
import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/release_metadata.py'
spec = importlib.util.spec_from_file_location('release_metadata', SCRIPT)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseMetadataTests(unittest.TestCase):
    def test_version_tags_match_application_and_prereleases(self):
        self.assertEqual(release.release_version('0.6.0', 'v0.6.0'), '0.6.0')
        self.assertEqual(release.release_version('0.6.0', 'v0.6.0-beta.1'), '0.6.0-beta.1')
        self.assertEqual(release.release_version('0.6.0'), '0.6.0')
        for tag in ['v0.7.0', 'v00.6.0', '0.6.0', 'v0.6.0-01', 'v0.6.0-beta..1', 'v0.6.0/../../other', 'v0.6.0\n']:
            with self.subTest(tag=tag), self.assertRaises(ValueError): release.release_version('0.6.0', tag)

    def fixture(self, app):
        for name in ['Contents/Info.plist', 'Contents/MacOS/Audifern', 'Contents/Resources/Audifern.icns',
                     'Contents/Resources/LICENSE.txt', 'Contents/Resources/SOURCE.txt', 'Contents/Resources/THIRD_PARTY_NOTICES.md',
                     'Contents/Resources/Audifern_Audifern.bundle/Contents/Info.plist',
                     *['Contents/Resources/Audifern_Audifern.bundle/Contents/Resources/' + resource for resource in release.RESOURCES]]:
            path = app / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(b'synthetic')

    def test_required_public_payload_and_missing_localization(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / 'Audifern.app'; self.fixture(app); release.vet_payload(app)
            (app / 'Contents/Resources/Audifern_Audifern.bundle/Contents/Resources/es.lproj/Localizable.strings').unlink()
            with self.assertRaises(ValueError): release.vet_payload(app)

    def test_authentication_file_cannot_enter_app(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / 'Audifern.app'; self.fixture(app)
            (app / 'Contents/Resources/utl-auth.json').write_text('{}')
            with self.assertRaises(ValueError): release.vet_payload(app)

    def test_native_swiftpm_flat_resource_bundle(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / 'Audifern.app'; self.fixture(app)
            bundle = app / 'Contents/Resources/Audifern_Audifern.bundle'
            (bundle / 'Contents/Info.plist').rename(bundle / 'Info.plist')
            for resource in (bundle / 'Contents/Resources').iterdir():
                resource.rename(bundle / resource.name)
            (bundle / 'Contents/Resources').rmdir(); (bundle / 'Contents').rmdir()
            release.vet_payload(app)
            (bundle / 'pt-BR.lproj').rename(bundle / 'pt-br.lproj')
            release.vet_payload(app)
            (bundle / 'private-token.json').write_text('{}')
            with self.assertRaises(ValueError): release.vet_payload(app)

    def test_unexpected_signature_files_and_symlinks_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / 'Audifern.app'; self.fixture(app)
            path = app / 'Contents/_CodeSignature/unexpected.key'; path.parent.mkdir(); path.write_bytes(b'synthetic')
            with self.assertRaises(ValueError): release.vet_payload(app)
            path.unlink(); (app / 'Contents/Resources/alias').symlink_to(app / 'Contents/Info.plist')
            with self.assertRaises(ValueError): release.vet_payload(app)

    def test_legal_notices_are_required_in_binary_downloads(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / 'Audifern.app'; self.fixture(app)
            (app / 'Contents/Resources/SOURCE.txt').unlink()
            with self.assertRaises(ValueError): release.vet_payload(app)

    def test_universal_requires_both_cpu_slices(self):
        self.assertEqual(release.expected_architectures('universal'), {'arm64', 'x86_64'})
        self.assertEqual(release.expected_architectures('arm64'), {'arm64'})
        with self.assertRaises(ValueError): release.expected_architectures('unsupported')


if __name__ == '__main__': unittest.main()
