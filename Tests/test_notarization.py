# SPDX-License-Identifier: GPL-3.0-only
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts'
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location('notarize_release', SCRIPTS / 'notarize-release.py')
notary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notary)
import verify_release as verification

SUBMISSION = '00000000-0000-4000-8000-000000000001'


class NotarizationTests(unittest.TestCase):
    def test_authentication_does_not_accept_ambiguous_credentials(self):
        self.assertEqual(notary.authentication('local-notary'), ['--keychain-profile', 'local-notary'])
        self.assertEqual(notary.authentication('', '/private/key.p8', 'EXAMPLEKEY'), ['--key', '/private/key.p8', '--key-id', 'EXAMPLEKEY'])
        for arguments in [('',), ('local', '/private/key.p8'), ('', '', 'EXAMPLEKEY'), ('', '/key.p8', 'EXAMPLEKEY', 'invalid')]:
            with self.subTest(arguments=arguments), self.assertRaises(ValueError): notary.authentication(*arguments)

    def test_submission_identity_and_status_must_match(self):
        self.assertEqual(notary.submission_status({'id': SUBMISSION, 'status': 'Accepted'}, SUBMISSION), (SUBMISSION, 'Accepted'))
        for data in [{'id': SUBMISSION, 'status': 'Success'}, {'id': 'not-a-uuid', 'status': 'Accepted'},
                     {'id': '00000000-0000-4000-8000-000000000002', 'status': 'Accepted'}]:
            with self.assertRaises(ValueError): notary.submission_status(data, SUBMISSION)

    def test_matching_submission_resumes_without_duplicate_upload(self):
        with tempfile.TemporaryDirectory() as folder:
            logs = Path(folder); archive = logs / 'test.zip'; archive.write_bytes(b'synthetic')
            stamp = logs / 'app-submission.json'
            stamp.write_text(json.dumps({'id': SUBMISSION, 'sha256': notary.digest(archive)}))
            with patch.object(notary.subprocess, 'run') as run:
                run.return_value = subprocess.CompletedProcess([], 0, json.dumps({'id': SUBMISSION, 'status': 'Accepted'}), '')
                self.assertEqual(notary.notarize(archive, 'app', ['--keychain-profile', 'local'], 30, logs), SUBMISSION)
                self.assertEqual([call.args[0][2] for call in run.call_args_list], ['info'])

    def test_rejected_submission_cannot_reach_packaging(self):
        with tempfile.TemporaryDirectory() as folder:
            logs = Path(folder); archive = logs / 'test.zip'; archive.write_bytes(b'synthetic')
            responses = [{'id': SUBMISSION}, {'id': SUBMISSION, 'status': 'Invalid'}, {'issues': ['synthetic']}]
            with patch.object(notary.subprocess, 'run') as run:
                run.side_effect = [subprocess.CompletedProcess([], 0, json.dumps(data), '') for data in responses]
                with self.assertRaisesRegex(ValueError, 'rejected'):
                    notary.notarize(archive, 'app', ['--keychain-profile', 'local'], 30, logs)
                self.assertEqual([call.args[0][2] for call in run.call_args_list], ['submit', 'info', 'log'])
                self.assertEqual(json.loads((logs / 'app-submission.json').read_text())['id'], SUBMISSION)

    def test_timeout_keeps_submission_for_retry(self):
        with tempfile.TemporaryDirectory() as folder:
            logs = Path(folder); archive = logs / 'test.zip'; archive.write_bytes(b'synthetic')
            with patch.object(notary.subprocess, 'run') as run, patch.object(notary.time, 'monotonic', side_effect=[0, 5]):
                run.side_effect = [subprocess.CompletedProcess([], 0, json.dumps(data), '') for data in
                                   [{'id': SUBMISSION}, {'id': SUBMISSION, 'status': 'In Progress'}]]
                with self.assertRaisesRegex(ValueError, 'resume'):
                    notary.notarize(archive, 'app', [], 1, logs)
                self.assertTrue((logs / 'app-submission.json').exists())

    def fixture(self, directory):
        prefix = 'Audifern-0.6.1-macos-universal'
        data = {'application': 'Audifern', 'version': '0.6.1', 'releaseVersion': '0.6.1',
                'sourceCommit': 'a' * 40, 'sourceRepository': verification.metadata.REPOSITORY,
                'minimumMacOS': '14.0', 'architectures': ['arm64', 'x86_64'], 'signing': 'developer-id',
                'notarized': True, 'hardenedRuntime': True, 'secureTimestamp': True, 'teamID': 'A1B2C3D4E5'}
        (directory / (prefix + '.dmg')).write_bytes(b'synthetic dmg')
        (directory / (prefix + '.zip')).write_bytes(b'synthetic zip')
        (directory / 'build-info.json').write_text(json.dumps(data))
        self.checksums(directory)
        return data

    def checksums(self, directory):
        paths = sorted(path for path in directory.iterdir() if path.name != 'SHA256SUMS')
        (directory / 'SHA256SUMS').write_text(''.join(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.name + '\n' for path in paths))

    def test_provenance_hashes_and_claims_fail_closed(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(verification.metadata, 'version', return_value='0.6.1'), \
                patch.object(verification.metadata, 'source_commit', return_value='a' * 40):
            directory = Path(folder); data = self.fixture(directory)
            self.assertEqual(verification.verify_downloads(directory, 'v0.6.1'), data)
            for key, value in [('notarized', False), ('signing', 'ad-hoc'), ('sourceCommit', 'b' * 40),
                               ('architectures', ['arm64']), ('secureTimestamp', False)]:
                changed = dict(data); changed[key] = value
                (directory / 'build-info.json').write_text(json.dumps(changed)); self.checksums(directory)
                with self.subTest(key=key), self.assertRaises(ValueError):
                    verification.verify_downloads(directory, 'v0.6.1')
            self.fixture(directory)
            (directory / 'Audifern-0.6.1-macos-universal.zip').write_bytes(b'modified')
            with self.assertRaisesRegex(ValueError, 'checksum'): verification.verify_downloads(directory, 'v0.6.1')
            self.fixture(directory)
            (directory / 'private.p12').write_bytes(b'synthetic key')
            with self.assertRaisesRegex(ValueError, 'exactly'): verification.verify_downloads(directory, 'v0.6.1')


if __name__ == '__main__':
    unittest.main()
