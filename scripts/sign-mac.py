"""Inside-out signing. Defaults to ad-hoc; AAVA_SIGN_IDENTITY selects a local identity."""
import os,pathlib,plistlib,subprocess,sys,tempfile
app=pathlib.Path(sys.argv[1]).resolve()
identity=os.environ.get('AAVA_SIGN_IDENTITY','-')
for attr in ['com.apple.FinderInfo','com.apple.ResourceFork']:
 subprocess.run(['xattr','-dr',attr,str(app)],capture_output=True)
 subprocess.run(['xattr','-d',attr,str(app)],capture_output=True)
framework=app/'Contents/Frameworks/Chromium Embedded Framework.framework'
for library in (framework/'Versions/A/Libraries').glob('*.dylib'):
 subprocess.run(['codesign','--force','--sign',identity,str(library)],check=True)
subprocess.run(['codesign','--force','--sign',identity,str(framework)],check=True)
with tempfile.TemporaryDirectory(prefix='aava-sign-') as tmp:
 entitlements=pathlib.Path(tmp)/'jit.plist';entitlements.write_bytes(plistlib.dumps({'com.apple.security.cs.allow-jit':True}))
 for helper in (app/'Contents/Frameworks').glob('*.app'):
  command=['codesign','--force','--sign',identity]
  if '(Renderer)' in helper.name or '(GPU)' in helper.name or helper.name=='Aava Helper.app':command+=['--entitlements',str(entitlements)]
  subprocess.run(command+[str(helper)],check=True)
subprocess.run(['xattr','-d','com.apple.FinderInfo',str(app)],capture_output=True)
subprocess.run(['codesign','--force','--sign',identity,str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
