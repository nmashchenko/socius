#!/usr/bin/env python3
"""Read limits through the documented Codex app-server. Never reads auth tokens."""
import json, os, pathlib, select, shutil, subprocess, sys, time

def main():
    candidates = [shutil.which('codex'), str(pathlib.Path.home()/'.local/bin/codex'), '/opt/homebrew/bin/codex', '/usr/local/bin/codex', '/Applications/Codex.app/Contents/Resources/codex']
    executable = next((p for p in candidates if p and os.access(p, os.X_OK)), None)
    if not executable:
        raise RuntimeError('Codex CLI not found. Install Codex and sign in, then refresh.')
    process = subprocess.Popen([executable, 'app-server'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=False)
    buffer = b''
    deadline = time.monotonic() + 15
    def send(message):
        process.stdin.write((json.dumps(message)+'\n').encode()); process.stdin.flush()
    def receive(expected):
        nonlocal buffer
        while time.monotonic() < deadline:
            while b'\n' in buffer:
                line, buffer = buffer.split(b'\n', 1)
                try: message = json.loads(line)
                except (ValueError, UnicodeDecodeError): continue
                if message.get('id') == expected:
                    if 'error' in message: raise RuntimeError(message['error'].get('message', 'Codex request failed'))
                    return message
            ready, _, _ = select.select([process.stdout], [], [], max(0, deadline-time.monotonic()))
            if ready:
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk: raise RuntimeError('Codex closed the connection. Check that you are signed in.')
                buffer += chunk
                if len(buffer) > 2_000_000: raise RuntimeError('Codex response exceeded the expected size.')
        raise RuntimeError('Codex usage request timed out. Try again after signing in.')
    try:
        send({'id': 1, 'method': 'initialize', 'params': {'clientInfo': {'name': 'socius', 'title': 'Socius', 'version': '0.1.0'}}})
        receive(1)
        send({'method': 'initialized'})
        send({'id': 2, 'method': 'account/rateLimits/read'})
        print(json.dumps(receive(2)))
    finally:
        process.terminate()
        try: process.wait(timeout=2)
        except subprocess.TimeoutExpired: process.kill(); process.wait()
if __name__ == '__main__':
    try: main()
    except Exception as error:
        print(str(error), file=sys.stderr); sys.exit(1)
