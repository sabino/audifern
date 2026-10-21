import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/sign_app.py'
spec = importlib.util.spec_from_file_location('sign_app', SCRIPT)
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class NestedSigningTests(unittest.TestCase):
    def test_shared_group_has_a_valid_team_prefix_and_no_bluetooth_permission_in_the_widget(self):
        for widget in [False, True]:
            values = signing.entitlements('A1B2C3D4E5', widget=widget)
            self.assertEqual(values['com.apple.security.application-groups'], ['A1B2C3D4E5.org.audifern.shared'])
            self.assertEqual(values.get('com.apple.security.app-sandbox', False), widget)
            self.assertNotIn('com.apple.security.device.bluetooth', values)
            self.assertNotIn('com.apple.application-identifier', values)
            self.assertNotIn('com.apple.developer.team-identifier', values)
        with self.assertRaises(ValueError): signing.entitlements('OTHER.invalid', widget=True)

    def test_ad_hoc_build_has_no_shared_container(self):
        self.assertEqual(signing.entitlements('', widget=False), {})
        self.assertEqual(signing.entitlements('', widget=True), {'com.apple.security.app-sandbox': True})

    def test_nested_extension_is_signed_before_host_and_uses_the_actual_certificate_team(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'Audifern.app'; widget = app / signing.WIDGET
            for bundle in [app, widget]:
                info = bundle / 'Contents/Info.plist'; info.parent.mkdir(parents=True, exist_ok=True)
                info.write_bytes(plistlib.dumps({'AudifernAppGroupIdentifier': 'UNTRUSTED.group'}))
            signed = []
            def run(arguments, **kwargs):
                if '--entitlements' in arguments:
                    entitlement = plistlib.loads(Path(arguments[arguments.index('--entitlements') + 1]).read_bytes())
                    signed.append((Path(arguments[-1]), entitlement))
                self.assertNotIn('--deep', arguments)
                return subprocess.CompletedProcess(arguments, 0, '', 'TeamIdentifier=A1B2C3D4E5\n')
            with patch.object(signing.subprocess, 'run', side_effect=run): signing.sign(app, 'Synthetic identity', hardened=True)
            self.assertEqual([item[0] for item in signed], [widget, app])
            for bundle, values in signed:
                self.assertEqual(values['com.apple.security.application-groups'], ['A1B2C3D4E5.org.audifern.shared'])
                self.assertEqual(plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())['AudifernAppGroupIdentifier'], 'A1B2C3D4E5.org.audifern.shared')


if __name__ == '__main__': unittest.main()
