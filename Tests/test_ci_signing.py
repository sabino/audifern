# SPDX-License-Identifier: GPL-3.0-only
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts'
sys.path.insert(0, str(SCRIPTS))
import ci_signing as signing
spec = importlib.util.spec_from_file_location('configure_ci_signing', SCRIPTS / 'configure-ci-signing.py')
configure = importlib.util.module_from_spec(spec); spec.loader.exec_module(configure)

CONTEXT = {'GITHUB_REPOSITORY': 'sabino/audifern', 'GITHUB_EVENT_NAME': 'workflow_dispatch', 'GITHUB_REF': 'refs/heads/main'}


def secret_fixture():
    boundary = 'PRIVATE KEY'
    return {'AUDIFERN_CERTIFICATE_P12': base64.b64encode(b'synthetic').decode(),
            'AUDIFERN_CERTIFICATE_PASSWORD': 'synthetic-password',
            'AUDIFERN_NOTARY_KEY': '-----BEGIN ' + boundary + '-----\nsynthetic\n-----END ' + boundary + '-----\n',
            'AUDIFERN_NOTARY_KEY_ID': 'EXAMPLEKEY1', 'AUDIFERN_NOTARY_ISSUER': '00000000-0000-4000-8000-000000000001',
            'AUDIFERN_SIGN_IDENTITY': 'A' * 40, 'AUDIFERN_TEAM_ID': 'A1B2C3D4E5'}


class CISigningTests(unittest.TestCase):
    def artifact_fixture(self, directory):
        prefix = 'Audifern-1.2.3-macos-universal'
        with zipfile.ZipFile(directory / (prefix + '.zip'), 'w') as archive:
            archive.writestr('Audifern.app/Contents/Info.plist', 'synthetic')
        (directory / (prefix + '.dmg')).write_bytes(b'synthetic')
        data = {'application': 'Audifern', 'releaseVersion': '1.2.3', 'version': '1.2.3',
                'sourceCommit': 'a' * 40, 'sourceRepository': 'https://github.com/sabino/audifern',
                'architectures': ['arm64', 'x86_64'], 'minimumMacOS': '14.0', 'signing': 'ad-hoc', 'notarized': False}
        (directory / 'build-info.json').write_text(json.dumps(data))
        self.rehash(directory)
        return data

    def rehash(self, directory):
        paths = sorted(path for path in directory.iterdir() if path.name != 'SHA256SUMS')
        (directory / 'SHA256SUMS').write_text(''.join(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.name + '\n' for path in paths))

    def test_unsigned_artifact_hashes_and_source_must_match_before_loading_keys(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder); data = self.artifact_fixture(directory)
            self.assertEqual(signing.validate_unsigned(directory, 'v1.2.3', 'a' * 40), data)
            with self.assertRaises(ValueError): signing.validate_unsigned(directory, 'v1.2.3', 'b' * 40)
            (directory / 'Audifern-1.2.3-macos-universal.zip').write_bytes(b'modified')
            with self.assertRaises(ValueError): signing.validate_unsigned(directory, 'v1.2.3', 'a' * 40)
            self.artifact_fixture(directory)
            (directory / 'extra.p12').write_bytes(b'synthetic')
            with self.assertRaises(ValueError): signing.validate_unsigned(directory, 'v1.2.3', 'a' * 40)

    def test_moved_tag_and_zip_escape_are_rejected_before_extraction(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder); self.artifact_fixture(directory)
            for filename in ['../outside', '/absolute', 'Audifern.app/../../outside']:
                with self.subTest(filename=filename):
                    with zipfile.ZipFile(directory / 'Audifern-1.2.3-macos-universal.zip', 'w') as archive:
                        archive.writestr(filename, 'synthetic')
                    self.rehash(directory)
                    with patch.dict(os.environ, CONTEXT), patch.object(signing, 'command', side_effect=['a' * 40, 'b' * 40 + '\trefs/tags/v1.2.3\n']) as command:
                        with self.assertRaisesRegex(ValueError, 'Unsafe path'):
                            signing.prepare(directory, directory, 'v1.2.3', 'a' * 40, 'b' * 40)
                        self.assertEqual(command.call_count, 2)
            self.artifact_fixture(directory)
            with patch.dict(os.environ, CONTEXT), patch.object(signing, 'command', side_effect=['a' * 40, 'c' * 40 + '\trefs/tags/v1.2.3\n']) as command:
                with self.assertRaisesRegex(ValueError, 'tag changed'):
                    signing.prepare(directory, directory, 'v1.2.3', 'a' * 40, 'b' * 40)
                self.assertEqual(command.call_count, 2)

    def test_only_the_main_dispatch_context_can_load_credentials(self):
        with patch.dict(os.environ, CONTEXT, clear=True): signing.trusted_context()
        for key, value in [('GITHUB_REF', 'refs/tags/v1.2.3'), ('GITHUB_REF', 'refs/heads/feature'),
                           ('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_REPOSITORY', 'fork/audifern')]:
            with self.subTest(key=key, value=value), patch.dict(os.environ, dict(CONTEXT, **{key: value}), clear=True):
                with self.assertRaises(ValueError): signing.trusted_context()

    def test_missing_or_malformed_credentials_fail_before_keychain_mutation(self):
        values = secret_fixture()
        for key in values:
            with self.subTest(key=key):
                invalid = dict(values); invalid[key] = ''
                with self.assertRaises(ValueError): signing.credentials(invalid)
        for key, value in [('AUDIFERN_CERTIFICATE_P12', '!invalid!'), ('AUDIFERN_NOTARY_ISSUER', 'bad'),
                           ('AUDIFERN_SIGN_IDENTITY', '-'), ('AUDIFERN_NOTARY_KEY', 'not a key')]:
            invalid = dict(values); invalid[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): signing.credentials(invalid)
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, dict(CONTEXT, RUNNER_TEMP=folder), clear=True), \
                patch.object(signing, 'command') as command:
            with self.assertRaises(ValueError): signing.setup(Path(folder) / 'state.json')
            command.assert_not_called()
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_command_errors_do_not_print_secret_arguments_or_output(self):
        sensitive = 'synthetic-password-do-not-log'
        with patch.object(signing.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, sensitive, sensitive)):
            with self.assertRaises(ValueError) as error:
                signing.command('Importing the signing identity', ['security', '-P', sensitive])
            self.assertNotIn(sensitive, str(error.exception))
        with patch.object(configure.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, sensitive.encode(), sensitive.encode())):
            with self.assertRaises(ValueError) as error: configure.run('Uploading credentials', ['gh', sensitive])
            self.assertNotIn(sensitive, str(error.exception))

    def test_wrong_imported_identity_is_cleaned_and_search_list_restored(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); calls = []
            def command(label, args):
                calls.append(args)
                if 'create-keychain' in args: Path(args[-1]).touch()
                if 'list-keychains' in args and '-s' not in args: return '"/synthetic/original.keychain-db"\n'
                if 'find-identity' in args: return '1) ' + 'B' * 40 + ' "Developer ID Application: Example (A1B2C3D4E5)"\n'
                return ''
            env = dict(CONTEXT, **secret_fixture(), RUNNER_TEMP=folder, GITHUB_OUTPUT=str(root / 'outputs'))
            with patch.dict(os.environ, env, clear=True), patch.object(signing, 'command', side_effect=command):
                with self.assertRaisesRegex(ValueError, 'does not match'): signing.setup(root / 'state.json')
            self.assertTrue(any('delete-keychain' in args for args in calls))
            self.assertTrue(any(args == ['security', 'list-keychains', '-d', 'user', '-s', '/synthetic/original.keychain-db'] for args in calls))
            self.assertEqual(list(root.iterdir()), [])

    def test_cleanup_cannot_delete_a_path_outside_runner_temp(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); state = root / 'state.json'
            state.write_text(json.dumps({'folder': '/not-owned', 'keychain': '/not-owned/signing.keychain-db', 'previousKeychains': []}))
            with patch.dict(os.environ, {'RUNNER_TEMP': folder}), patch.object(signing, 'command') as command:
                with self.assertRaises(ValueError): signing.cleanup(state)
                command.assert_not_called()

    def test_provisioning_requires_consent_before_any_export_or_network_call(self):
        args = ['configure-ci-signing.py', '--identity', 'A' * 40, '--team', 'A1B2C3D4E5', '--key', '/synthetic.p8',
                '--key-id', 'EXAMPLEKEY1', '--issuer', '00000000-0000-4000-8000-000000000001']
        with patch.object(sys, 'argv', args), patch.object(configure, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'No credential transfer'): configure.main()
            run.assert_not_called()

    def test_provisioning_rejects_tag_and_wildcard_environment_policies(self):
        settings = {'deployment_branch_policy': {'protected_branches': False, 'custom_branch_policies': True}}
        for policies in [[{'name': 'main', 'type': 'branch'}], [{'name': 'v*', 'type': 'tag'}],
                         [{'name': '*', 'type': 'branch'}], [{'name': 'main', 'type': 'branch'}, {'name': 'v*', 'type': 'tag'}]]:
            with self.subTest(policies=policies), patch.object(configure, 'run', side_effect=[
                    json.dumps(settings).encode(), json.dumps({'branch_policies': policies}).encode()]):
                if policies == [{'name': 'main', 'type': 'branch'}]: configure.verify_environment()
                else:
                    with self.assertRaises(ValueError): configure.verify_environment()


if __name__ == '__main__':
    unittest.main()
