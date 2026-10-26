"""Stage, Developer ID sign, notarize, staple, and verify a direct Mac release.

No credentials are accepted on the command line: use a notarytool Keychain profile.
A saved submission is resumed after a timeout rather than submitted twice.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile


def run(command):
    return subprocess.run(command, check=True, text=True, capture_output=True)


def save(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def archive(app, path):
    run(['ditto', '-c', '-k', '--norsrc', '--keepParent', str(app), str(path)])


def checksum(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--work-dir', required=True, type=Path, help='Dedicated local directory outside synced folders; retained for resume.')
    parser.add_argument('--identity', required=True)
    parser.add_argument('--team-id', required=True)
    parser.add_argument('--keychain-profile', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build-number', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+', args.version) or not args.build_number.isdigit():
        parser.error('Use a numeric x.y.z bundle version and numeric build number.')
    work = args.work_dir.expanduser().resolve()
    source = args.app.expanduser().resolve()
    if work == source or source in work.parents or work in source.parents:
        parser.error('The release work directory must be separate from the source app.')
    work.mkdir(parents=True, exist_ok=True)
    state_path = work / 'notarization-state.json'
    app = work / 'Aava.app'
    submitted = work / 'submission.zip'
    settings = {'version': args.version, 'build': args.build_number, 'team': args.team_id,
                'identity': args.identity, 'profile': args.keychain_profile, 'source': str(source)}
    state = json.loads(state_path.read_text()) if state_path.exists() else {'settings': settings}
    if state['settings'] != settings:
        parser.error('This directory belongs to another release; use a fresh work directory.')
    if not state.get('submissionID'):
        if app.exists():
            parser.error('A staged app already exists without a recorded submission. Inspect it and use a fresh work directory; nothing was overwritten.')
        # Confirm credentials before copying or signing. Never print credential contents.
        run(['xcrun', 'notarytool', 'history', '--keychain-profile', args.keychain_profile, '--output-format', 'json'])
        run(['ditto', '--norsrc', str(source), str(app)])
        info = app / 'Contents/Info.plist'
        config = plistlib.loads(info.read_bytes())
        config.update(CFBundleIdentifier='app.geeklab.aava', CFBundleName='Aava', CFBundleDisplayName='Aava',
                      CFBundleShortVersionString=args.version, CFBundleVersion=args.build_number,
                      LSEnvironment={'MallocNanoZone': '0'})
        info.write_bytes(plistlib.dumps(config))
        for helper in (app / 'Contents/Frameworks').glob('Aava Helper*.app'):
            info = helper / 'Contents/Info.plist'
            config = plistlib.loads(info.read_bytes())
            config['CFBundleIdentifier'] = config['CFBundleIdentifier'].replace('app.geeklab.aava.dev.helper', 'app.geeklab.aava.helper')
            config.update(CFBundleShortVersionString=args.version, CFBundleVersion=args.build_number)
            info.write_bytes(plistlib.dumps(config))
        run([sys.executable, str(Path(__file__).with_name('sign-mac.py')), str(app), '--distribution',
             '--identity', args.identity, '--team-id', args.team_id])
        archive(app, submitted)
        response = run(['xcrun', 'notarytool', 'submit', str(submitted), '--keychain-profile', args.keychain_profile, '--output-format', 'json'])
        (work / 'submission-response.json').write_text(response.stdout)
        result = json.loads(response.stdout)
        state['submissionID'] = result['id']
        state['submittedSHA256'] = checksum(submitted)
        save(state_path, state)
    submission = state['submissionID']
    print('Notarization submission: ' + submission, flush=True)
    if not submitted.is_file() or checksum(submitted) != state['submittedSHA256']:
        parser.error('The submitted archive changed; resume refused.')
    # Timeout leaves the submission ID and signed app available for an explicit resume.
    subprocess.run(['xcrun', 'notarytool', 'wait', submission, '--keychain-profile', args.keychain_profile, '--timeout', '10m', '--output-format', 'json'], text=True, capture_output=True)
    result = json.loads(run(['xcrun', 'notarytool', 'info', submission, '--keychain-profile', args.keychain_profile, '--output-format', 'json']).stdout)
    state['status'] = result['status']
    save(state_path, state)
    if result['status'] == 'In Progress':
        parser.exit(1, 'Apple is still processing this submission. Run the same command to resume; no release ZIP was created.\n')
    run(['xcrun', 'notarytool', 'log', submission, '--keychain-profile', args.keychain_profile, str(work / 'notarization-log.json')])
    if result['status'] != 'Accepted':
        parser.exit(1, 'Apple has not accepted this build. No release ZIP was created. See notarization-log.json.\n')
    run(['xcrun', 'stapler', 'staple', str(app)])
    run(['xcrun', 'stapler', 'validate', str(app)])
    run(['codesign', '--verify', '--deep', '--strict', str(app)])
    run(['spctl', '--assess', '--type', 'execute', '--verbose=2', str(app)])
    final = work / ('Aava-' + args.version + '-macos-arm64.zip')
    candidate = work / 'verified-candidate.zip'
    archive(app, candidate)
    # Check the actual shipped bytes after extraction, not only the pre-archive bundle.
    # Preserve failed inspections while allowing the same submission to be retried.
    extracted = Path(tempfile.mkdtemp(prefix='package-check-', dir=work))
    run(['ditto', '-x', '-k', str(candidate), str(extracted)])
    for command in [['codesign', '--verify', '--deep', '--strict'], ['xcrun', 'stapler', 'validate'], ['spctl', '--assess', '--type', 'execute']]:
        run(command + [str(extracted / 'Aava.app')])
    candidate.replace(final)
    digest = checksum(final)
    final.with_suffix('.zip.sha256').write_text(digest + '  ' + final.name + '\n')
    state.update(status='Accepted', stapled=True, gatekeeperAccepted=True, archive=final.name, sha256=digest)
    save(state_path, state)
    print('Verified notarized artifact: ' + str(final))


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as exc:
        sys.exit('Release step failed. No completion claimed.\n' + (exc.stderr or str(exc)))
