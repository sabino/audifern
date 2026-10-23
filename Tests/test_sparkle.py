# SPDX-License-Identifier: GPL-3.0-only
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts'
sys.path.insert(0, str(SCRIPTS))
import sparkle_framework as framework
import sparkle_appcast as appcast


class SparklePayloadTests(unittest.TestCase):
    def fixture(self, directory):
        bundle = directory / 'Sparkle.framework'
        resources = bundle / 'Versions/B/Resources'; resources.mkdir(parents=True)
        info = {'CFBundleIdentifier': 'org.sparkle-project.Sparkle', 'CFBundleShortVersionString': '2.10.0'}
        (resources / 'Info.plist').write_bytes(plistlib.dumps(info))
        (resources / 'Notice.txt').write_text('Synthetic reviewed resource')
        (bundle / 'Resources').symlink_to('Versions/B/Resources')
        files = {p.relative_to(bundle).as_posix(): {'executable': False, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                 for p in resources.iterdir()}
        manifest = {'version': '2.10.0', 'bundleIdentifier': info['CFBundleIdentifier'],
                    'files': files, 'symlinks': {'Resources': 'Versions/B/Resources'}}
        return bundle, manifest

    def test_only_pinned_files_resources_and_internal_symlinks_are_allowed(self):
        for mutation in ['extra', 'modified', 'escape', 'permissions', 'missing']:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                bundle, manifest = self.fixture(Path(temporary))
                framework.verify_payload(bundle, manifest=manifest)
                resource = bundle / 'Versions/B/Resources/Notice.txt'
                if mutation == 'extra': (bundle / 'private.p12').write_bytes(b'synthetic')
                elif mutation == 'modified': resource.write_text('Changed')
                elif mutation == 'escape':
                    (bundle / 'Resources').unlink(); (bundle / 'Resources').symlink_to('/tmp')
                elif mutation == 'permissions': resource.chmod(0o700)
                else: resource.unlink()
                with self.assertRaises(ValueError): framework.verify_payload(bundle, manifest=manifest)


class AppcastTests(unittest.TestCase):
    def fixture(self):
        signature = base64.b64encode(bytes(64)).decode()
        data = f'''<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><item>
<sparkle:version>21</sparkle:version><sparkle:shortVersionString>0.9.0</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
<enclosure url="https://github.com/sabino/audifern/releases/download/v0.9.0/Audifern-0.9.0-macos-universal.zip" length="10" sparkle:edSignature="{signature}" />
</item></channel></rss>'''
        return data, {'CFBundleVersion': '21'}, {'releaseVersion': '0.9.0'}

    def test_feed_must_match_the_single_release_archive_build_and_minimum_os(self):
        data, info, manifest = self.fixture()
        appcast.validate_feed(data.encode(), info, manifest, 10)
        mutations = [data.replace('>21<', '>20<'), data.replace('>14.0<', '>12.0<'),
                     data.replace('github.com', 'example.com'), data.replace('length="10"', 'length="11"'),
                     data.replace('<item>', '<item/><item>'), data.replace('sparkle:edSignature', 'unsigned'),
                     data.replace('<rss ', '<!DOCTYPE rss><rss ')]
        for mutated in mutations:
            with self.subTest(mutated=mutated[:100]), self.assertRaises(ValueError):
                appcast.validate_feed(mutated.encode(), info, manifest, 10)

    def test_update_secret_cannot_be_used_from_prs_or_tags(self):
        for event, ref in [('pull_request', 'refs/pull/1/merge'), ('push', 'refs/tags/v0.9.0'), ('workflow_dispatch', 'refs/heads/feature')]:
            environment = {'GITHUB_ACTIONS': 'true', 'GITHUB_REPOSITORY': 'sabino/audifern', 'GITHUB_EVENT_NAME': event,
                           'GITHUB_REF': ref, 'AUDIFERN_UPDATE_PRIVATE_KEY': 'synthetic-never-used'}
            with self.subTest(event=event, ref=ref), patch.dict(os.environ, environment, clear=True), patch.object(appcast, 'tools') as tools:
                with self.assertRaisesRegex(ValueError, 'trusted main'): appcast.create(Path('/synthetic'))
                tools.assert_not_called()

    def test_an_ad_hoc_or_unnotarized_archive_cannot_receive_a_release_feed(self):
        for signing, notarized in [('ad-hoc', False), ('developer-id', False), ('ad-hoc', True)]:
            with self.subTest(signing=signing, notarized=notarized), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                (directory / 'build-info.json').write_text(json.dumps({'signing': signing, 'notarized': notarized, 'releaseVersion': '0.9.0'}))
                environment = {'AUDIFERN_UPDATE_PRIVATE_KEY': base64.b64encode(bytes(32)).decode()}
                with patch.dict(os.environ, environment, clear=True), patch.object(appcast, 'tools') as tools:
                    with self.assertRaisesRegex(ValueError, 'notarized Developer ID'): appcast.create(directory)
                    tools.assert_not_called()
                    self.assertNotIn('AUDIFERN_UPDATE_PRIVATE_KEY', os.environ)
                    self.assertFalse((directory / 'appcast.xml').exists())

    @unittest.skipUnless(sys.platform == 'darwin' and shutil.which('swift'), 'CryptoKit verification requires macOS Swift')
    def test_public_verifier_rejects_tampered_feed_and_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            generator = directory / 'fixture.swift'
            generator.write_text('''import CryptoKit
import Foundation
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let key = Curve25519.Signing.PrivateKey()
let archive = Data("Synthetic archive".utf8)
try archive.write(to: folder.appendingPathComponent("archive.zip"))
let signature = try key.signature(for: archive).base64EncodedString()
let content = Data("<?xml version=\\"1.0\\"?><rss/>\\n".utf8)
let feedSignature = try key.signature(for: content).base64EncodedString()
var feed = content
feed.append(Data("<!-- sparkle-signatures:\\nedSignature: \\(feedSignature)\\nlength: \\(content.count)\\n-->\\n".utf8))
try feed.write(to: folder.appendingPathComponent("appcast.xml"))
let metadata = ["public": key.publicKey.rawRepresentation.base64EncodedString(), "archiveSignature": signature]
try JSONSerialization.data(withJSONObject: metadata).write(to: folder.appendingPathComponent("public.json"))
''')
            subprocess.run(['swift', str(generator), str(directory)], check=True, capture_output=True)
            public = json.loads((directory / 'public.json').read_text())
            executable = directory / 'verify-signature'
            subprocess.run(['swiftc', str(SCRIPTS / 'verify-update-signature.swift'), '-o', str(executable)], check=True, capture_output=True)
            for mode, name, extra in [('feed', 'appcast.xml', []), ('archive', 'archive.zip', [public['archiveSignature']])]:
                args = [str(executable), mode, public['public'], str(directory / name), *extra]
                subprocess.run(args, check=True, capture_output=True)
                with (directory / name).open('ab') as output: output.write(b'tampered')
                self.assertNotEqual(subprocess.run(args, capture_output=True).returncode, 0)


if __name__ == '__main__': unittest.main()
