#!/usr/bin/env python3
"""Claude status-line bridge: save only rate limits, never conversation or auth data."""
import json, os, pathlib, sys, tempfile

def main():
    payload = json.load(sys.stdin)
    limits = payload.get('rate_limits', {})
    directory = pathlib.Path.home() / 'Library/Application Support/Socius'
    directory.mkdir(parents=True, exist_ok=True)
    safe = {}
    for key in ('five_hour', 'seven_day', 'spend_limit'):
        value = limits.get(key)
        if isinstance(value, dict):
            safe[key] = {k: value[k] for k in ('used_percentage', 'resets_at') if isinstance(value.get(k), (int, float))}
    fd, path = tempfile.mkstemp(dir=directory, prefix='.claude-usage-')
    try:
        with os.fdopen(fd, 'w') as file: json.dump({'rate_limits': safe}, file)
        os.replace(path, directory / 'claude-usage.json')
    finally:
        if os.path.exists(path): os.unlink(path)
    print(' · '.join(f'{label}: {safe[key]["used_percentage"]:.0f}% used' for key, label in [('five_hour','5h'),('seven_day','7d')] if 'used_percentage' in safe.get(key, {})) or 'Socius · waiting for usage')
if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, TypeError): print('Socius · usage unavailable')
