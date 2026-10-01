#!/usr/bin/env python3
"""Finish a downloaded update after the running GTK process exits."""

from pathlib import Path
import shutil
import subprocess
import sys
import time


def main() -> None:
    pid = int(sys.argv[1])
    package = Path(sys.argv[2])
    prefix = Path(sys.argv[3])
    while Path(f"/proc/{pid}").exists():
        time.sleep(0.2)
    try:
        subprocess.run([sys.executable, str(package / "install.py"), "--prefix", str(prefix)], check=True)
        subprocess.Popen([str(prefix / "bin/dayline")], start_new_session=True)
    finally:
        shutil.rmtree(package.parent)


if __name__ == "__main__":
    main()
