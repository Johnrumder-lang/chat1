#!/usr/bin/env python3
"""Run the actual weather lifecycle against deterministic Roblox service stand-ins."""
from pathlib import Path
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parents[1]
spec=(root/'tests/weather_spec.luau').read_text()
source=(root/'src/server/Weather.lua').read_text()
with tempfile.TemporaryDirectory(prefix='northbound-weather-') as folder:
    script=Path(folder)/'weather_spec.luau'
    script.write_text(spec.replace('-- WEATHER_MODULE',source))
    result=subprocess.run([sys.argv[1] if len(sys.argv)>1 else 'luau',str(script)],check=False)
    raise SystemExit(result.returncode)
