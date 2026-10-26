#!/usr/bin/env python3
"""Integration checks; run only against the isolated QA app and mini.html fixture."""
import argparse, base64, importlib.util, json, pathlib, socket, stat, time
spec = importlib.util.spec_from_file_location('mini', pathlib.Path(__file__).with_name('aava-mini.py'))
mini = importlib.util.module_from_spec(spec); spec.loader.exec_module(mini)
parser = argparse.ArgumentParser(); parser.add_argument('--connection', required=True); args=parser.parse_args()
connection = pathlib.Path(args.connection)
checks=[]
def check(name, condition):
    assert condition, name
    checks.append(name); print('PASS', name)
def call(method, **kw): return mini.connect(connection, dict(method=method, **kw))
def snap():
    result=call('snapshot'); assert result['ok'], result
    return result['result']
s=snap(); assert s['url']=='http://127.0.0.1:8769/mini.html', 'Only the synthetic QA fixture is supported'
refs={n['name']:n['ref'] for n in s['nodes']}
check('private manifest and directory', stat.S_IMODE(connection.stat().st_mode)==0o600 and stat.S_IMODE(connection.parent.stat().st_mode)==0o700)
check('isolated ready session', call('status')['isolated'] and call('status')['ready'])
check('fill', call('fill',ref=refs['Note'],text='Written in Mini only')['ok'])
check('select', call('select',ref=refs['Theme'],text='tide')['ok'])
check('click', call('click',ref=refs['Count click'])['ok'])
check('separate storage write', call('click',ref=refs['Remember here'])['ok'])
s2=snap(); check('visible outcomes', 'Written in Mini only' in s2['text'] and 'Clicks: 1' in s2['text'] and 'Storage: mini-only' in s2['text'] and 'Cookie: mini_proof=mini-only' in s2['text'])
check('old reference rejected', not call('click',ref=refs['Count click'])['ok'])
check('unsupported arbitrary script rejected', not call('evaluate',script='1+1')['ok'])
check('local file navigation rejected', not call('navigate',url='file:///etc/passwd')['ok'])
check('scroll', call('scroll',amount=200)['ok'])
image=call('screenshot'); check('rendered PNG', image['ok'] and base64.b64decode(image['png']).startswith(b'\x89PNG'))
refs={n['name']:n['ref'] for n in s2['nodes']}
check('file picker blocked', call('click',ref=refs['File check'])['ok']); time.sleep(.15)
check('file access notice', 'File access' in call('status')['notice'])
check('popup blocked', call('click',ref=refs['Popup check'])['ok']); time.sleep(.15)
check('popup remains in same page', call('status')['url']==s['url'] and 'Popup blocked' in call('status')['notice'])
m=json.loads(connection.read_text())
with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as client:
    client.connect(m['socket']);client.sendall(json.dumps(dict(method='status',token='wrong',session=m['session'])).encode()+b'\n'); r=json.loads(client.recv(4096))
check('wrong token rejected', not r['ok'])
print(f'{len(checks)} integration checks passed')
