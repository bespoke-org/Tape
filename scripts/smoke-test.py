#!/usr/bin/env python3
"""Build and exercise the packaged app with isolated data and a bounded run time."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
modes = parser.add_mutually_exclusive_group()
modes.add_argument('--continuation', action='store_true', help='Verify continuation focus, rejection, cancellation, and timer completion')
modes.add_argument('--system-activity', action='store_true', help='Verify lock/sleep notification handling with private notification centers')
modes.add_argument('--creation', action='store_true', help='Verify drawing and task selection')
modes.add_argument('--timeline', action='store_true', help='Verify timeline navigation and zoom across two launches')
modes.add_argument('--overwrite', action='store_true', help='Verify Command-drag overwrite and cancellation')
modes.add_argument('--dismissal', action='store_true', help='Verify outside-click dismissal after color menu use')
modes.add_argument('--editing', action='store_true', help='Verify inline entry correction, resizing, and deletion')
args = parser.parse_args()
run_timeout = 40 if args.editing or args.continuation else 20
root = Path(__file__).resolve().parent.parent
app = root / 'build/smoke/Line.app'
subprocess.run([str(root / 'scripts/build-app.sh'), 'debug'], cwd=root,
               env=dict(os.environ, LINE_APP_OUTPUT=str(app)), check=True, timeout=180)
output = root / 'build' / ('continuation-smoke-results' if args.continuation else 'system-activity-smoke-results' if args.system_activity else 'dismissal-smoke-results' if args.dismissal else 'editing-smoke-results' if args.editing else 'overwrite-smoke-results' if args.overwrite else 'creation-smoke-results' if args.creation else 'timeline-smoke-results' if args.timeline else 'smoke-results')
output.mkdir(parents=True, exist_ok=True)
report = output / 'result.txt'

with tempfile.TemporaryDirectory(prefix='line-smoke-') as data:
    for launch in range(2 if args.timeline else 1):
        report.unlink(missing_ok=True)
        try:
            result = subprocess.run(
                [str(app / 'Contents/MacOS/Line'), '--smoke-test', str(output)],
                env=dict(os.environ, LINE_DATA_DIRECTORY=data, LINE_SMOKE_CONTINUATION='1' if args.continuation else '0', LINE_SMOKE_SYSTEM_ACTIVITY='1' if args.system_activity else '0', LINE_SMOKE_DISMISSAL='1' if args.dismissal else '0', LINE_SMOKE_TIMELINE='1' if args.timeline else '0',
                         LINE_SMOKE_EDITING='1' if args.editing else '0', LINE_SMOKE_CREATION='1' if args.creation else '0', LINE_SMOKE_OVERWRITE='1' if args.overwrite else '0'),
                capture_output=True, text=True, timeout=run_timeout,
            )
        except subprocess.TimeoutExpired:
            raise SystemExit(f'Smoke check exceeded {run_timeout} seconds. The test app was terminated.')
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
        if args.continuation:
            assert len(records['entries']) >= 2
            assert all(entry.get('end') is not None for entry in records['entries'])
        elif args.system_activity:
            assert len(records['entries']) == 2
            assert len(records['tasks']) == 2
            assert all(entry.get('end') is not None for entry in records['entries'])
        elif args.timeline:
            assert records['timelineSpan'] == 14_400 / (2 ** (launch + 1))
            assert records['entries'] == []
        elif args.editing or args.dismissal:
            assert len(records['entries']) == 1
            assert len(records['tasks']) == 1
            assert all(entry.get('end') is not None for entry in records['entries'])
        elif args.overwrite:
            assert len(records['entries']) == 3
            assert len(records['tasks']) == 2
            assert all(entry.get('end') is not None for entry in records['entries'])
        elif args.creation:
            assert len(records['entries']) == 3
            assert len(records['tasks']) == 1
            assert all(entry.get('end') is not None for entry in records['entries'])
        else:
            assert len(records['entries']) == 7
            assert all(entry.get('end') is not None for entry in records['entries'])
    print('PASS: saved zoom survived a fresh process.' if args.timeline else
          'PASS: packaged app exited with completed entries saved.')
