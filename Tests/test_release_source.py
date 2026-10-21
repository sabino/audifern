# SPDX-License-Identifier: GPL-3.0-only
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import release_source


class ReleaseSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory(prefix='af-gpg-', dir='/tmp')
        cls.root = Path(cls.work.name)
        cls.home = cls.root / 'keys'; cls.home.mkdir(mode=0o700)
        cls.env = dict(os.environ, GNUPGHOME=str(cls.home))
        subprocess.run(['gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase', '', '--quick-generate-key',
                        'Release Tests <release@example.invalid>', 'ed25519', 'sign', '0'], env=cls.env, capture_output=True, check=True)
        keys = subprocess.check_output(['gpg', '--batch', '--with-colons', '--list-secret-keys'], env=cls.env, text=True)
        cls.fingerprint = next(line.split(':')[9] for line in keys.splitlines() if line.startswith('fpr:'))
        cls.public = cls.root / 'public.asc'
        cls.public.write_bytes(subprocess.check_output(['gpg', '--batch', '--armor', '--export', cls.fingerprint], env=cls.env))

    @classmethod
    def tearDownClass(cls):
        subprocess.run(['gpgconf', '--kill', 'gpg-agent'], env=cls.env, capture_output=True)
        cls.work.cleanup()

    def git(self, repo, *args):
        return subprocess.check_output(['git', '-c', 'commit.gpgsign=false', '-c', 'tag.gpgsign=false',
                '-c', 'gpg.program=gpg', '-c', 'gpg.format=openpgp', '-c', 'user.name=Release Tests',
                '-c', 'user.email=release@example.invalid', *args], cwd=repo, env=self.env, text=True, stderr=subprocess.DEVNULL).strip()

    def fixture(self, folder):
        repo = Path(folder)
        self.git(repo, 'init', '-b', 'main')
        (repo / 'Resources').mkdir()
        (repo / 'Resources/Info.plist').write_bytes(plistlib.dumps(
            {'CFBundleIdentifier': 'org.audifern.app', 'CFBundleShortVersionString': '1.2.3'}))
        self.git(repo, 'add', 'Resources/Info.plist')
        self.git(repo, 'commit', '-m', 'Synthetic release')
        commit = self.git(repo, 'rev-parse', 'HEAD')
        self.git(repo, 'update-ref', 'refs/remotes/origin/main', commit)
        return repo, commit

    def sign(self, repo, tag):
        self.git(repo, 'tag', '-s', '-u', self.fingerprint, tag, '-m', 'Synthetic release')

    def test_signed_main_tag_resolves_to_immutable_objects(self):
        with tempfile.TemporaryDirectory() as folder:
            repo, commit = self.fixture(folder)
            self.sign(repo, 'v1.2.3')
            result = release_source.verify_tag(repo, 'v1.2.3', self.public, self.fingerprint)
            self.assertEqual(result, {'tag': 'v1.2.3', 'version': '1.2.3', 'commit': commit,
                                     'tagObject': self.git(repo, 'rev-parse', 'refs/tags/v1.2.3')})

    def test_unsigned_tags_and_wrong_signer_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            repo, _ = self.fixture(folder)
            self.git(repo, 'tag', 'v1.2.3')
            with self.assertRaisesRegex(ValueError, 'annotated'): release_source.verify_tag(repo, 'v1.2.3', self.public, self.fingerprint)
            self.git(repo, 'tag', '-d', 'v1.2.3')
            self.git(repo, 'tag', '-a', 'v1.2.3', '-m', 'Unsigned annotation')
            with self.assertRaisesRegex(ValueError, 'valid signature'): release_source.verify_tag(repo, 'v1.2.3', self.public, self.fingerprint)
            self.git(repo, 'tag', '-d', 'v1.2.3')
            self.sign(repo, 'v1.2.3')
            with self.assertRaisesRegex(ValueError, 'approved maintainer'): release_source.verify_tag(repo, 'v1.2.3', self.public, 'F' * 40)

    def test_signed_tag_outside_main_and_version_mismatch_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            repo, _ = self.fixture(folder)
            self.sign(repo, 'v1.2.4')
            with self.assertRaisesRegex(ValueError, 'match Info.plist'): release_source.verify_tag(repo, 'v1.2.4', self.public, self.fingerprint)
            self.git(repo, 'switch', '-c', 'unreviewed')
            (repo / 'change.txt').write_text('synthetic')
            self.git(repo, 'add', 'change.txt'); self.git(repo, 'commit', '-m', 'Outside main')
            self.sign(repo, 'v1.2.3')
            with self.assertRaisesRegex(ValueError, 'merge-base'): release_source.verify_tag(repo, 'v1.2.3', self.public, self.fingerprint)


if __name__ == '__main__':
    unittest.main()
