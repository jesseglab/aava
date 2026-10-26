"""Sign nested CEF code inside-out, with an explicit distribution mode."""
import argparse
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


def run(command):
    return subprocess.run(command, check=True, text=True, capture_output=True)


def sign_app(app, identity, distribution=False, hardened=False, team=None):
    app = Path(app).resolve()
    if not (app / 'Contents/Info.plist').is_file():
        raise ValueError('Expected an assembled .app bundle.')
    if distribution:
        identities = run(['security', 'find-identity', '-v', '-p', 'codesigning']).stdout
        matches = re.findall(r'([A-Fa-f0-9]{40}) "([^"]+)"', identities)
        selected = [name for fingerprint, name in matches if identity in (fingerprint, name)]
        if len(selected) != 1 or not selected[0].startswith('Developer ID Application:'):
            raise ValueError('Distribution requires one installed Developer ID Application identity, not a development or ad-hoc certificate.')
        if not team or not selected[0].endswith('(' + team + ')'):
            raise ValueError('The Developer ID identity must match the explicitly selected team.')
        hardened = True
    if hardened and identity == '-':
        raise ValueError('Hardened-runtime validation requires a real signing identity.')
    framework = app / 'Contents/Frameworks/Chromium Embedded Framework.framework'
    helper_names = ['Aava Helper' + suffix + '.app' for suffix in ['', ' (Alerts)', ' (GPU)', ' (Plugin)', ' (Renderer)']]
    helpers = [app / 'Contents/Frameworks' / name for name in helper_names]
    if not framework.is_dir() or any(not helper.is_dir() for helper in helpers):
        raise ValueError('Incomplete CEF framework/helper bundle.')
    for attr in ['com.apple.FinderInfo', 'com.apple.ResourceFork']:
        subprocess.run(['xattr', '-dr', attr, str(app)], capture_output=True)
    base = ['codesign', '--force', '--sign', identity]
    if hardened:
        base += ['--timestamp']
    signed = []
    for library in sorted((framework / 'Versions/A/Libraries').glob('*.dylib')):
        run(base + [str(library)])
        signed.append(library)
    run(base + [str(framework)])
    signed.append(framework)
    with tempfile.TemporaryDirectory(prefix='aava-entitlements-') as tmp:
        tmp = Path(tmp)
        # Match Chromium 156's renderer/GPU roles. Device access still needs user consent.
        entitlements = {
            'jit': {'com.apple.security.cs.allow-jit': True},
            'helper': {},
            'app': {'com.apple.security.device.audio-input': True,
                    'com.apple.security.device.camera': True},
        }
        for name, values in entitlements.items():
            (tmp / (name + '.plist')).write_bytes(plistlib.dumps(values))
        for helper in helpers:
            role = 'jit' if '(Renderer)' in helper.name or '(GPU)' in helper.name else 'helper'
            # Preserve the existing development behavior for non-hardened local builds.
            if not hardened and helper.name == 'Aava Helper.app':
                role = 'jit'
            command = base + (['--options', 'runtime'] if hardened else [])
            run(command + ['--entitlements', str(tmp / (role + '.plist')), str(helper)])
            signed.append(helper)
        command = base + (['--options', 'runtime'] if hardened else [])
        run(command + ['--entitlements', str(tmp / 'app.plist'), str(app)])
        signed.append(app)
    run(['codesign', '--verify', '--deep', '--strict', str(app)])
    for path in signed:
        details = run(['codesign', '--display', '--verbose=4', str(path)]).stderr
        if hardened and 'Timestamp=' not in details:
            raise ValueError('Missing secure timestamp: ' + str(path))
        if hardened and path.suffix == '.app' and 'runtime' not in details:
            raise ValueError('Missing hardened runtime: ' + str(path))
        if distribution and ('Authority=Developer ID Application:' not in details or 'TeamIdentifier=' + team not in details):
            raise ValueError('Unexpected distribution identity: ' + str(path))
    print('Verified ' + ('distribution' if distribution else 'hardened development' if hardened else 'development') + ' signatures: ' + str(app))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--identity', default=os.environ.get('AAVA_SIGN_IDENTITY', '-'))
    parser.add_argument('--distribution', action='store_true')
    parser.add_argument('--hardened-runtime', action='store_true', help='Validate hardened runtime using a development identity; not a distribution signature.')
    parser.add_argument('--team-id')
    args = parser.parse_args()
    try:
        sign_app(args.app, args.identity, args.distribution, args.hardened_runtime, args.team_id)
    except (ValueError, subprocess.CalledProcessError) as exc:
        parser.exit(1, str(exc) + '\n' + getattr(exc, 'stderr', '') + '\n')


if __name__ == '__main__':
    main()
