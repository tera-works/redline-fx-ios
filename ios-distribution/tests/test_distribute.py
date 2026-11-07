import copy
import importlib.util
import plistlib
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('distribution', Path(__file__).parents[1] / 'scripts/distribute.py')
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)


class DistributionTests(unittest.TestCase):
    def entry(self, version='1.0.0', build='1', bid='org.test.app'):
        return {'name': 'Test', 'bundleIdentifier': bid, 'versions': [{'version': version, 'buildVersion': build}], '_sha256': 'internal'}

    def test_history_sorted_numerically_and_multiple_apps(self):
        source = d.assemble('Test', [self.entry('1.9.0'), self.entry('1.10.0', '2'), self.entry(bid='org.test.other')])
        app = next(a for a in source['apps'] if a['bundleIdentifier'] == 'org.test.app')
        self.assertEqual([v['version'] for v in app['versions']], ['1.10.0', '1.9.0'])
        self.assertEqual(len(source['apps']), 2)
        self.assertNotIn('_sha256', app)

    def test_duplicate_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            d.assemble('Test', [self.entry(), self.entry()])

    def test_ipa_validation(self):
        info = {'CFBundleIdentifier': 'org.test.app', 'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0.0', 'MinimumOSVersion': '16.0', 'CFBundleExecutable': 'Test', 'CFBundleSupportedPlatforms': ['iPhoneOS']}
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'test.ipa'
            def make(extra=None, settings=None):
                with zipfile.ZipFile(path, 'w') as z:
                    z.writestr('Payload/Test.app/Info.plist', plistlib.dumps(settings or info))
                    z.writestr('Payload/Test.app/Test', b'fixture')
                    if extra:
                        z.writestr(extra, b'fixture')
            make()
            self.assertEqual(d.inspect_ipa(path)['CFBundleVersion'], '1')
            make('Payload/Test.app/embedded.mobileprovision')
            with self.assertRaisesRegex(ValueError, 'Signed'):
                d.inspect_ipa(path)
            make('../escape')
            with self.assertRaisesRegex(ValueError, 'Unsafe'):
                d.inspect_ipa(path)
            simulator = copy.deepcopy(info)
            simulator['CFBundleSupportedPlatforms'] = ['iPhoneSimulator']
            make(settings=simulator)
            with self.assertRaisesRegex(ValueError, 'device'):
                d.inspect_ipa(path)


if __name__ == '__main__':
    unittest.main()
