#!/usr/bin/env python3
"""Build and exercise the packaged app with isolated data and a 20-second run limit."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--timeline', action='store_true', help='Verify timeline navigation and zoom across two launches')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
app = root / 'build/smoke/Line.app'
subprocess.run([str(root / 'scripts/build-app.sh'), 'debug'], cwd=root,
               env=dict(os.environ, LINE_APP_OUTPUT=str(app)), check=True, timeout=180)
output = root / 'build' / ('timeline-smoke-results' if args.timeline else 'smoke-results')
output.mkdir(parents=True, exist_ok=True)
report = output / 'result.txt'

with tempfile.TemporaryDirectory(prefix='line-smoke-') as data:
    for launch in range(2 if args.timeline else 1):
        report.unlink(missing_ok=True)
        try:
            result = subprocess.run(
                [str(app / 'Contents/MacOS/Line'), '--smoke-test', str(output)],
                env=dict(os.environ, LINE_DATA_DIRECTORY=data, LINE_SMOKE_TIMELINE='1' if args.timeline else '0'),
                capture_output=True, text=True, timeout=20,
            )
        except subprocess.TimeoutExpired:
            raise SystemExit('Smoke check exceeded 20 seconds. The test app was terminated.')
        if result.stdout:
            print(result.stdout, end='')
        if result.stderr:
            print(result.stderr, end='')
        if report.exists():
            print(report.read_text(), end='')
        else:
            raise SystemExit('Smoke check did not produce a result.')
        if result.returncode:
            raise SystemExit(result.returncode)
        records = json.loads((Path(data) / 'tracking.json').read_text())
        if args.timeline:
            assert records['timelineSpan'] == 14_400 / (2 ** (launch + 1))
            assert records['entries'] == []
        else:
            assert len(records['entries']) == 7
            assert all(entry.get('end') is not None for entry in records['entries'])
    print('PASS: saved zoom survived a fresh process.' if args.timeline else
          'PASS: packaged app exited with completed entries saved.')
