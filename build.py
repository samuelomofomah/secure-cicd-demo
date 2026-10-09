#!/usr/bin/env python3
"""BUILD: turn the source in site/ into the finished product in dist/.

The page is a template. This script fills in the release number, the change ID
and the publish time, so anyone looking at the live site can tell exactly which
version they are seeing. The template engine (Jinja2) is open-source code
written by someone else, which is why the pipeline scans it for known
vulnerabilities before using it.
"""
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined, select_autoescape

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "site"
OUT = ROOT / "dist"


def main() -> None:
    release = os.environ.get("BUILD_NUMBER", "local")
    change_id = os.environ.get("COMMIT_SHA", "local")[:7]
    published = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir()

    env = Environment(
        loader=FileSystemLoader(SRC),
        autoescape=select_autoescape(default=True),
        undefined=StrictUndefined,  # a missing value is an error, not a blank
    )
    page = env.get_template("index.html.j2").render(
        release=release, change_id=change_id, published=published
    )
    (OUT / "index.html").write_text(page, encoding="utf-8")

    for item in SRC.iterdir():
        if item.is_file() and item.suffix != ".j2":
            shutil.copy2(item, OUT / item.name)

    print(f"Built release #{release} ({change_id}) into dist/")


if __name__ == "__main__":
    main()
