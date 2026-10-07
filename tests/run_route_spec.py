#!/usr/bin/env python3
"""Execute actual Route.lua with deterministic Roblox math stand-ins in Luau CLI."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
spec = (root / "tests/route_spec.luau").read_text()
route = (root / "src/shared/Route.lua").read_text()
program = spec.replace("-- ROUTE_MODULE", "local Route = (function()\n" + route + "\nend)()")
with tempfile.TemporaryDirectory(prefix="roadtrip-route-spec-") as directory:
    test = Path(directory) / "route_spec.luau"
    test.write_text(program)
    result = subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(test)], check=False)
    raise SystemExit(result.returncode)
