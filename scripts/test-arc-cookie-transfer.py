"""Run the native cookie-transfer harness twice, using only synthetic cookies.

Build Aava first. Set AAVA_SIGN_IDENTITY to the same local identity used for previous
runs if macOS Keychain requires it. This never reads Arc or real browser profiles.
"""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
workspace = Path(tempfile.mkdtemp(prefix='aava-cookie-integration-', dir='/private/tmp'))
app = workspace / 'Aava Cookie Test.app'
data = workspace / 'data'
subprocess.run(['cp', '-cR', str(root / 'build/mac/Aava.app'), str(app)], check=True)
info = app / 'Contents/Info.plist'
config = plistlib.loads(info.read_bytes())
config.update(CFBundleIdentifier='app.geeklab.aava.cookietest', CFBundleName='Aava Cookie Test',
              CFBundleDisplayName='Aava Cookie Test', LSEnvironment={'AAVA_DATA_DIRECTORY': str(data)})
info.write_bytes(plistlib.dumps(config))
command = ['xcrun', 'clang++', '-std=c++20', '-arch', 'arm64', '-mmacosx-version-min=14.0',
           '-fobjc-arc', '-DCEF_USE_SANDBOX', '-DCEF_API_VERSION=15600', '-Ivendor/cef',
           '-IApps/macOS/Sources', 'Tests/Native/ArcCookieTransferTest.mm', 'build/mac/Engine.o',
           'build/mac/ChromeHost.o', 'build/mac/Main.o', 'build/cef/libcef_dll_wrapper/libcef_dll_wrapper.a',
           '-framework', 'Cocoa', '-framework', 'IOSurface', '-framework', 'QuartzCore',
           '-o', str(app / 'Contents/MacOS/Aava')]
subprocess.run(command, cwd=root, check=True)
subprocess.run([sys.executable, str(root / 'scripts/sign-mac.py'), str(app)], check=True)
for phase in ('transfer', 'restart'):
    with (workspace / (phase + '.log')).open('w') as log:
        subprocess.run([str(app / 'Contents/MacOS/Aava')], cwd=root,
                       env={**os.environ, 'AAVA_DATA_DIRECTORY': str(data)},
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=45)
    result = json.loads((data / (phase + '-result.json')).read_text())
    if not result['passed']:
        raise SystemExit(result)
    print(phase + ': ' + result['detail'])
print('Synthetic results retained at ' + str(workspace))
