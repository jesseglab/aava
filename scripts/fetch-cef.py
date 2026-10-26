import hashlib,json,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
lock=json.loads((root/'Apps/macOS/cef-version.json').read_text())
vendor=root/'vendor';vendor.mkdir(exist_ok=True)
archive=vendor/'cef.tar.bz2'
def valid():
 if not archive.exists() or archive.stat().st_size!=lock['size']:return False
 digest=hashlib.sha1()
 with archive.open('rb') as f:
  for chunk in iter(lambda:f.read(1024*1024),b''):digest.update(chunk)
 return digest.hexdigest()==lock['sha1']
if not valid():
 subprocess.run(['curl','-fL','--retry','2','https://cef-builds.spotifycdn.com/'+lock['name'],'-o',str(archive)],check=True)
 if not valid():raise SystemExit('CEF archive checksum mismatch; extraction stopped.')
dest=vendor/'cef';dest.mkdir(exist_ok=True)
subprocess.run(['tar','-xjf',str(archive),'--exclude','*/Debug','-C',str(dest),'--strip-components=1'],check=True)
print('Verified and extracted CEF',lock['version'])
