#!/usr/bin/env python3
"""Aava Mini's local, session-scoped client. Python standard library only."""
import argparse
import base64
import json
import os
import pathlib
import socket
import stat
import sys


def connect(path, request):
    path = pathlib.Path(path)
    details = path.stat()
    if details.st_uid != os.getuid() or stat.S_IMODE(details.st_mode) & 0o077:
        raise ValueError('Connection file must be private and owned by you.')
    manifest = json.loads(path.read_text())
    if manifest.get('version') != 1:
        raise ValueError('Unsupported Mini connection version.')
    socket_path = pathlib.Path(manifest['socket'])
    if socket_path.parent.resolve() != path.parent.resolve():
        raise ValueError('Socket must belong to this connection directory.')
    request = dict(request, token=manifest['token'], session=manifest['session'])
    packet = json.dumps(request).encode() + b'\n'
    if len(packet) > 65536:
        raise ValueError('Request is too large (64 KiB maximum).')
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(12)
        client.connect(str(socket_path))
        client.sendall(packet)
        response = bytearray()
        while len(response) <= 8 * 1024 * 1024:
            chunk = client.recv(65536)
            if not chunk:
                raise ValueError('Mini closed the connection. Check the session in Aava.')
            response.extend(chunk)
            if b'\n' in chunk:
                return json.loads(response.split(b'\n', 1)[0])
        raise ValueError('Mini response exceeded the size limit.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--connection', required=True, help='Exact connection path from Aava’s copied prompt')
    sub = parser.add_subparsers(dest='method', required=True)
    for name in ('status', 'snapshot', 'stop', 'request'):
        sub.add_parser(name)
    sub.add_parser('navigate').add_argument('url')
    sub.add_parser('click').add_argument('ref')
    for name in ('fill', 'select'):
        command = sub.add_parser(name)
        command.add_argument('ref')
        command.add_argument('--text', required=True)
    sub.add_parser('scroll').add_argument('amount', type=int)
    sub.add_parser('screenshot').add_argument('--output', required=True)
    args = vars(parser.parse_args())
    path, output = args.pop('connection'), args.pop('output', None)
    try:
        if args['method'] == 'request':
            args = json.loads(sys.stdin.read(65537))
            if not isinstance(args, dict):
                raise ValueError('Request must be a JSON object.')
        result = connect(path, args)
        if output and result.get('ok') and result.get('png'):
            image = base64.b64decode(result.pop('png'), validate=True)
            target = pathlib.Path(output).expanduser()
            # Refuse to overwrite an existing file or follow a symlink.
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, 'wb') as stream:
                stream.write(image)
            result['output'] = str(target)
        print(json.dumps(result, ensure_ascii=False))
        return 0 if result.get('ok') else 1
    except (OSError, ValueError, KeyError, TypeError):
        # Avoid exposing connection contents, tokens or entered text in exceptions.
        print(json.dumps({'ok': False, 'error': 'Mini connection or request failed. Check the session and arguments; never fall back to your regular browser.'}))
        return 1


if __name__ == '__main__':
    sys.exit(main())
