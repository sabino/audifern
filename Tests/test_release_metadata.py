# SPDX-License-Identifier: GPL-3.0-only
import importlib.util
from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import tempfile
import sys
import unittest
from unittest.mock import patch
import subprocess

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/release_metadata.py'
sys.path.insert(0, str(SCRIPT.parent))
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
                     *['Contents/Resources/Audifern_Audifern.bundle/Contents/Resources/' + resource for resource in release.RESOURCES],
                     *[release.WIDGET + name for name in release.WIDGET_FILES]]:
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

    def test_widget_payload_has_the_same_strict_privacy_boundary(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / 'Audifern.app'; self.fixture(app); release.vet_payload(app)
            secret = app / release.WIDGET / 'Contents/Resources/authentication.json'
            secret.write_text('{}')
            with self.assertRaises(ValueError): release.vet_payload(app)
            secret.unlink()
            (app / release.WIDGET / 'Contents/MacOS/AudifernWidgets').unlink()
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

    def test_developer_id_requires_hardened_runtime_and_secure_timestamp(self):
        details = release.parse_signing_details(
            'CodeDirectory v=20500 size=500 flags=0x10000(runtime) hashes=10+7\n'
            'Authority=Developer ID Application: Example (A1B2C3D4E5)\n'
            'Authority=Developer ID Certification Authority\nTeamIdentifier=A1B2C3D4E5\n'
            'Timestamp=Oct 20, 2026 at 1:00:00 PM\n')
        self.assertEqual(details, {'signing': 'developer-id', 'hardenedRuntime': True,
                                  'secureTimestamp': True, 'teamID': 'A1B2C3D4E5'})
        with patch.object(release, 'signing_details', return_value=details), patch.object(release.subprocess, 'run') as run:
            run.return_value = subprocess.CompletedProcess([], 0, '', 'source=Notarized Developer ID\n')
            release.verify_notarization(Path('/synthetic.app'), 'A1B2C3D4E5')
            with self.assertRaises(ValueError):
                release.verify_notarization(Path('/synthetic.app'), 'DIFFERENT1')
            run.return_value.stderr = 'source=Unnotarized Developer ID\n'
            with self.assertRaises(ValueError): release.verify_notarization(Path('/synthetic.app'))
            for key in ['hardenedRuntime', 'secureTimestamp', 'teamID']:
                with self.subTest(key=key):
                    original = details[key]; details[key] = None
                    run.reset_mock()
                    with self.assertRaises(ValueError): release.verify_notarization(Path('/synthetic.app'))
                    run.assert_not_called()
                    details[key] = original

    def test_ad_hoc_and_development_certificates_are_not_developer_id(self):
        for text in ['Signature=adhoc\nTeamIdentifier=not set\n',
                     'Authority=Apple Development: Example\nTeamIdentifier=A1B2C3D4E5\n']:
            details = release.parse_signing_details(text)
            self.assertNotEqual(details['signing'], 'developer-id')
            with patch.object(release, 'signing_details', return_value=details), patch.object(release.subprocess, 'run') as run:
                with self.assertRaises(ValueError): release.verify_notarization(Path('/synthetic.app'))
                run.assert_not_called()

    def test_ticket_validation_retries_service_failure_then_still_requires_gatekeeper(self):
        details = {'signing': 'developer-id', 'hardenedRuntime': True,
                   'secureTimestamp': True, 'teamID': 'A1B2C3D4E5'}
        with patch.object(release, 'signing_details', return_value=details), \
                patch.object(release.subprocess, 'run') as run, patch.object(release.apple_tickets.time, 'sleep') as sleep:
            run.side_effect = [subprocess.CompletedProcess([], 68, 'service unavailable', ''),
                               subprocess.CompletedProcess([], 0, '', ''),
                               subprocess.CompletedProcess([], 0, '', 'source=Notarized Developer ID\n')]
            release.verify_notarization(Path('/synthetic.app'), 'A1B2C3D4E5')
            self.assertEqual([call.args[0][:3] for call in run.call_args_list],
                             [['xcrun', 'stapler', 'validate']] * 2 + [['spctl', '--assess', '--type']])
            sleep.assert_called_once_with(15)

    def test_ticket_retry_keeps_manifest_stdout_valid_json(self):
        details = {'signing': 'developer-id', 'hardenedRuntime': True,
                   'secureTimestamp': True, 'teamID': 'A1B2C3D4E5'}
        failures = [subprocess.CompletedProcess([], 68, 'service unavailable', ''),
                    subprocess.TimeoutExpired(['xcrun', 'stapler'], 60)]
        for failure in failures:
            with self.subTest(failure=type(failure).__name__):
                output = io.StringIO(); diagnostics = io.StringIO()
                with patch.object(sys, 'argv', ['release_metadata.py', 'manifest', '/synthetic.app', '--notarized']), \
                        patch.object(release, 'verify_app', return_value={'version': '0.6.0'}), \
                        patch.object(release, 'version', return_value='0.6.0'), \
                        patch.object(release, 'source_commit', return_value='a' * 40), \
                        patch.object(release, 'signing_details', return_value=details), \
                        patch.object(release.subprocess, 'run') as run, \
                        patch.object(release.apple_tickets.time, 'sleep') as sleep, \
                        redirect_stdout(output), redirect_stderr(diagnostics):
                    run.side_effect = [failure, subprocess.CompletedProcess([], 0, '', ''),
                                       subprocess.CompletedProcess([], 0, '', 'source=Notarized Developer ID\n')]
                    release.main()
                manifest = json.loads(output.getvalue())
                self.assertIs(manifest['notarized'], True)
                self.assertEqual(manifest['teamID'], details['teamID'])
                self.assertIn('retrying in 15 seconds', diagnostics.getvalue())
                sleep.assert_called_once_with(15)
                self.assertEqual(run.call_args.args[0][:3], ['spctl', '--assess', '--type'])

    def test_invalid_or_revoked_ticket_stops_before_gatekeeper(self):
        details = {'signing': 'developer-id', 'hardenedRuntime': True,
                   'secureTimestamp': True, 'teamID': 'A1B2C3D4E5'}
        for code in [65, 77]:
            with self.subTest(code=code), patch.object(release, 'signing_details', return_value=details), \
                    patch.object(release.subprocess, 'run') as run, patch.object(release.apple_tickets.time, 'sleep') as sleep:
                run.return_value = subprocess.CompletedProcess([], code, 'synthetic invalid ticket', '')
                with self.assertRaisesRegex(ValueError, 'validation failed'):
                    release.verify_notarization(Path('/synthetic.app'), 'A1B2C3D4E5')
                self.assertEqual(run.call_count, 1)
                sleep.assert_not_called()

    def test_stapled_ticket_is_allowed_but_extra_credentials_are_not(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / 'Audifern.app'; self.fixture(app)
            (app / 'Contents/CodeResources').write_bytes(b'synthetic ticket')
            release.vet_payload(app)
            (app / 'Contents/auth.p12').write_bytes(b'synthetic credential')
            with self.assertRaises(ValueError): release.vet_payload(app)


if __name__ == '__main__': unittest.main()
