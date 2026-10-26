"""Release gates, without Apple credentials or network access."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('notarization', ROOT / 'scripts/notarize-mac.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class NotarizationGates(unittest.TestCase):
    def scenario(self, status, fail_gatekeeper=False, corrupt_archive=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        work = Path(temporary.name)
        source = Path('/tmp/aava-gate-source.app').resolve()
        (work / 'Aava.app').mkdir()
        (work / 'submission.zip').write_bytes(b'signed submission')
        settings = {'version': '0.3.0', 'build': '4', 'team': 'TESTTEAM',
                    'identity': 'Developer ID Application: Test (TESTTEAM)', 'profile': 'test', 'source': str(source)}
        state = {'settings': settings, 'submissionID': 'existing-submission',
                 'submittedSHA256': hashlib.sha256(b'signed submission').hexdigest()}
        (work / 'notarization-state.json').write_text(json.dumps(state))
        if corrupt_archive:
            (work / 'submission.zip').write_bytes(b'changed')
        commands = []

        def run(command):
            commands.append(command)
            if command[:3] == ['xcrun', 'notarytool', 'info']:
                return subprocess.CompletedProcess(command, 0, json.dumps({'status': status}), '')
            if fail_gatekeeper and command[0] == 'spctl':
                raise subprocess.CalledProcessError(1, command, stderr='rejected')
            if command[:3] == ['ditto', '-x', '-k']:
                (Path(command[-1]) / 'Aava.app').mkdir(parents=True)
            return subprocess.CompletedProcess(command, 0, '', '')

        args = ['notarize-mac.py', '--app', str(source), '--work-dir', str(work), '--identity', settings['identity'],
                '--team-id', 'TESTTEAM', '--keychain-profile', 'test', '--version', '0.3.0', '--build-number', '4']
        with patch('sys.argv', args), patch.object(module, 'run', side_effect=run), \
             patch.object(module.subprocess, 'run'), \
             patch.object(module, 'archive', side_effect=lambda app, path: path.write_bytes(b'stapled app')):
            try:
                module.main()
                outcome = 'success'
            except (SystemExit, subprocess.CalledProcessError):
                outcome = 'stopped'
        return work, commands, outcome

    def test_rejection_never_exports_release(self):
        work, commands, result = self.scenario('Invalid')
        self.assertEqual(result, 'stopped')
        self.assertFalse(list(work.glob('Aava-*.zip')))
        self.assertFalse(any(c[:2] == ['xcrun', 'stapler'] for c in commands))
        self.assertTrue(any(c[:3] == ['xcrun', 'notarytool', 'log'] for c in commands))

    def test_processing_preserves_submission_without_resubmitting(self):
        work, commands, result = self.scenario('In Progress')
        self.assertEqual(result, 'stopped')
        self.assertFalse(list(work.glob('Aava-*.zip')))
        self.assertFalse(any(c[:3] == ['xcrun', 'notarytool', 'submit'] for c in commands))
        self.assertEqual(json.loads((work / 'notarization-state.json').read_text())['submissionID'], 'existing-submission')
        self.assertEqual(json.loads((work / 'notarization-state.json').read_text())['status'], 'In Progress')

    def test_gatekeeper_failure_stops_release(self):
        work, commands, result = self.scenario('Accepted', fail_gatekeeper=True)
        self.assertTrue(any(c[0] == 'spctl' for c in commands))
        self.assertEqual(result, 'stopped')
        self.assertFalse(list(work.glob('Aava-*.zip')))

    def test_modified_submission_cannot_resume(self):
        work, commands, result = self.scenario('Accepted', corrupt_archive=True)
        self.assertEqual(result, 'stopped')
        self.assertFalse(commands)
        self.assertFalse(list(work.glob('Aava-*.zip')))

    def test_accepted_release_checks_extracted_app_and_writes_checksum(self):
        work, commands, result = self.scenario('Accepted')
        self.assertEqual(result, 'success')
        self.assertTrue((work / 'Aava-0.3.0-macos-arm64.zip.sha256').is_file())
        self.assertEqual(len([c for c in commands if c[0] == 'spctl']), 2)
        state = json.loads((work / 'notarization-state.json').read_text())
        self.assertTrue(state['gatekeeperAccepted'])
        self.assertTrue(state['stapled'])


if __name__ == '__main__':
    unittest.main()
