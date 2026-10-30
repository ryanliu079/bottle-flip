#!/usr/bin/env python3
"""Read the debug scene validation report from a simulator's app container."""
import json, os, subprocess, sys
from pathlib import Path

device = sys.argv[1] if len(sys.argv) > 1 else 'booted'
env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
container = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device,
                                     'com.ryanliu.bottleflip.prototype', 'data'], env=env, text=True).strip()
report = Path(container) / 'Documents/landing-validation.json'
if not report.exists():
    print('Validation report not available yet.')
    sys.exit(2)
result = json.loads(report.read_text())
print(json.dumps(result, indent=2))
if result['complete']:
    destination = Path(__file__).resolve().parent.parent / 'build/landing-validation.json'
    destination.parent.mkdir(exist_ok=True)
    destination.write_text(json.dumps(result, indent=2) + '\n')
sys.exit(0 if result['complete'] and result['passed'] else 1)
