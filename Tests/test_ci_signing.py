# SPDX-License-Identifier: GPL-3.0-only
import base64
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import stat
import shutil
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
    def policy_fixture(self):
        permissions = {'enabled': True, 'allowed_actions': 'selected', 'sha_pinning_required': True}
        allowed = {'github_owned_allowed': False, 'verified_allowed': False, 'patterns_allowed': sorted(configure.ACTIONS)}
        owner = [{'actor_id': 982190, 'actor_type': 'User', 'bypass_mode': 'always'}]
        def policy(target, ref, rules, bypass):
            return {'enforcement': 'active', 'target': target, 'bypass_actors': bypass,
                    'conditions': {'ref_name': {'include': [ref], 'exclude': []}}, 'rules': rules}
        rulesets = [
            policy('branch', 'refs/heads/main', [
                {'type': 'deletion'}, {'type': 'non_fast_forward'}, {'type': 'required_signatures'},
                {'type': 'required_status_checks', 'parameters': {
                    'strict_required_status_checks_policy': True,
                    'required_status_checks': [{'context': name, 'integration_id': 15368} for name in configure.CHECKS]}}
            ], []),
            policy('branch', 'refs/heads/main', [{'type': 'update', 'parameters': {'update_allows_fetch_and_merge': False}}], owner),
            policy('tag', 'refs/tags/v*', [
                {'type': 'update', 'parameters': {'update_allows_fetch_and_merge': False}}, {'type': 'deletion'}
            ], []),
            policy('tag', 'refs/tags/v*', [{'type': 'creation'}], owner),
        ]
        return permissions, allowed, rulesets

    def test_credential_upload_rejects_weakened_repository_policy(self):
        fixture = self.policy_fixture()
        configure.validate_repository_policy(*fixture)
        def mutate_missing_check(items): items[2][0]['rules'][-1]['parameters']['required_status_checks'].pop()
        def mutate_check_origin(items): items[2][0]['rules'][-1]['parameters']['required_status_checks'][0]['integration_id'] = 1
        def mutate_owner(items): items[2][1]['bypass_actors'].append({'actor_id': 1, 'actor_type': 'User', 'bypass_mode': 'always'})
        changes = {
            'unpinned actions': lambda x: x[0].update(sha_pinning_required=False),
            'unreviewed action': lambda x: x[1]['patterns_allowed'].append('other/action@' + 'a' * 40),
            'all first-party actions': lambda x: x[1].update(github_owned_allowed=True),
            'quality bypass': lambda x: x[2][0].update(bypass_actors=x[2][1]['bypass_actors']),
            'missing signatures': lambda x: x[2][0]['rules'].pop(2),
            'missing check': mutate_missing_check,
            'spoofed check source': mutate_check_origin,
            'another main updater': mutate_owner,
            'disabled main policy': lambda x: x[2][1].update(enforcement='disabled'),
            'wrong branch': lambda x: x[2][1]['conditions']['ref_name'].update(include=['refs/heads/feature']),
            'mutable tags': lambda x: x[2][2].update(bypass_actors=x[2][1]['bypass_actors']),
            'no tag creation restriction': lambda x: x[2].pop(3),
        }
        for name, change in changes.items():
            with self.subTest(name=name):
                invalid = copy.deepcopy(fixture); change(invalid)
                with self.assertRaises(ValueError): configure.validate_repository_policy(*invalid)

    def test_repository_audit_checks_the_github_account_before_other_calls(self):
        with patch.object(configure, 'run', return_value=b'{"login":"another-account"}') as run:
            with self.assertRaisesRegex(ValueError, 'sabino GitHub account'): configure.verify_repository_policy()
            self.assertEqual(run.call_count, 1)

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

    def test_only_the_reviewed_sparkle_symlink_is_allowed_before_extraction(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder); self.artifact_fixture(directory)
            (directory / 'scripts').mkdir()
            (directory / 'scripts/sparkle-payload.json').write_text(json.dumps({'symlinks': {'Versions/Current': 'B'}}))
            for target in ['B', '../../../../outside']:
                with self.subTest(target=target):
                    with zipfile.ZipFile(directory / 'Audifern-1.2.3-macos-universal.zip', 'w') as archive:
                        link = zipfile.ZipInfo('Audifern.app/Contents/Frameworks/Sparkle.framework/Versions/Current')
                        link.create_system = 3; link.external_attr = (stat.S_IFLNK | 0o777) << 16
                        archive.writestr(link, target)
                    # Keep only the expected release files in the artifact directory.
                    paths = sorted(path for path in directory.iterdir() if path.is_file() and path.name != 'SHA256SUMS')
                    (directory / 'SHA256SUMS').write_text(''.join(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.name + '\n' for path in paths))
                    artifacts = directory / 'artifacts'; artifacts.mkdir(exist_ok=True)
                    for path in paths + [directory / 'SHA256SUMS']: shutil.copyfile(path, artifacts / path.name)
                    with patch.dict(os.environ, CONTEXT), patch.object(signing, 'command', side_effect=['a' * 40, 'b' * 40 + '\trefs/tags/v1.2.3\n', '', '']) as command:
                        if target == 'B':
                            signing.prepare(directory, artifacts, 'v1.2.3', 'a' * 40, 'b' * 40)
                            self.assertEqual(command.call_count, 4)
                        else:
                            with self.assertRaisesRegex(ValueError, 'symlink'):
                                signing.prepare(directory, artifacts, 'v1.2.3', 'a' * 40, 'b' * 40)
                            self.assertEqual(command.call_count, 2)

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
