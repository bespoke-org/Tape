#!/usr/bin/env python3
"""Build and exercise the packaged app with isolated data and a 20-second run limit."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
app = root / "build/smoke/Line.app"
subprocess.run([str(root / "scripts/build-app.sh"), "debug"], cwd=root,
               env=dict(os.environ, LINE_APP_OUTPUT=str(app)), check=True, timeout=180)
output = root / "build/smoke-results"
output.mkdir(parents=True, exist_ok=True)
report = output / "result.txt"
report.unlink(missing_ok=True)

with tempfile.TemporaryDirectory(prefix="line-smoke-") as data:
    try:
        result = subprocess.run(
            [str(app / "Contents/MacOS/Line"), "--smoke-test", str(output)],
            env=dict(os.environ, LINE_DATA_DIRECTORY=data),
            capture_output=True, text=True, timeout=20,
        )
    except subprocess.TimeoutExpired:
        raise SystemExit("Smoke check exceeded 20 seconds. The test app was terminated.")
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    if report.exists():
        print(report.read_text(), end="")
    else:
        raise SystemExit("Smoke check did not produce a result.")
    if result.returncode:
        raise SystemExit(result.returncode)

    # Reopen the real store after the app exits; clean shutdown must have fixed every endpoint.
    import json
    records = json.loads((Path(data) / "tracking.json").read_text())
    assert len(records["entries"]) == 2
    assert all(entry.get("end") is not None for entry in records["entries"])
    print("PASS: packaged app exited with completed entries saved.")
