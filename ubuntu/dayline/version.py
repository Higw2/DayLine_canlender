"""Version embedded in the source tree or installed Ubuntu package."""

from pathlib import Path

VERSION = (Path(__file__).resolve().parent.parent / "VERSION").read_text(encoding="utf-8").strip()
