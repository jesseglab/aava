"""Package an isolated preview without replacing Aava or importing another browser."""
import argparse, os, pathlib, plistlib, subprocess, sys
parser=argparse.ArgumentParser()
parser.add_argument('--destination', required=True, type=pathlib.Path)
parser.add_argument('--data-directory', required=True, type=pathlib.Path)
args=parser.parse_args()
source=pathlib.Path('build/mac/Aava.app').resolve()
dest=args.destination.expanduser().resolve()
if dest.exists():
    raise SystemExit('Destination exists. Quit the preview and choose a new destination; no bundle is overwritten.')
if not source.exists():
    raise SystemExit('Build Aava first with scripts/build-mac.sh.')
dest.parent.mkdir(parents=True,exist_ok=True)
subprocess.run(['ditto','--norsrc',str(source),str(dest)],check=True,env={**os.environ,'COPYFILE_DISABLE':'1'})
info=dest/'Contents/Info.plist'
config=plistlib.loads(info.read_bytes())
config.update(CFBundleIdentifier='app.geeklab.aava.preview',CFBundleName='Aava Preview Development',CFBundleDisplayName='Aava Preview',LSEnvironment={'AAVA_DATA_DIRECTORY':str(args.data_directory.expanduser().resolve())})
info.write_bytes(plistlib.dumps(config))
subprocess.run([sys.executable,'scripts/sign-mac.py',str(dest)],check=True)
print(dest)
