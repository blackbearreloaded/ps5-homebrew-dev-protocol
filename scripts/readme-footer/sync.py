#!/usr/bin/env python3
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
"""Write the standard README footer into every configured repository.

Usage:
  sync.py ROOT            rewrite the footer in ROOT/<repo>/README.md
  sync.py --check ROOT    exit 1 if any footer differs from the template

ROOT is a directory that holds one clone per repository, named as in
repos.toml. The footer sits between the bbr-footer markers at the end of
each README; everything above the markers is left alone.
"""
import argparse
import pathlib
import sys
import tomllib

HERE = pathlib.Path(__file__).resolve().parent
START = "<!-- bbr-footer:start -->"
END = "<!-- bbr-footer:end -->"


def render(template, config, name):
    settings = {**config["defaults"], **config["repos"][name]}
    text = config["text"]
    license_text = settings["license"] or text["license"]
    if settings["releases"]:
        license_text += " " + text["releases"]
    if settings["license_extra"]:
        license_text += " " + settings["license_extra"]
    return template.format(
        sdk_line=text[settings["sdk"]],
        license=license_text,
        trademarks=settings["trademarks"],
        gpl_ref=text["gpl_ref"] if settings["gpl"] else "",
        risk=text["risk"] if settings["risk"] else "",
    )


def apply(readme, footer):
    start = readme.find(START)
    if start < 0:
        return readme.rstrip("\n") + "\n\n" + footer
    end = readme.index(END, start) + len(END)
    return readme[:start] + footer.rstrip("\n") + readme[end:]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("root", type=pathlib.Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    template = (HERE / "template.md").read_text(encoding="utf-8")
    config = tomllib.loads((HERE / "repos.toml").read_text(encoding="utf-8"))
    stale = []
    for name in config["repos"]:
        path = args.root / name / "README.md"
        if not path.exists():
            print(f"skip {name}: no README.md under {args.root}")
            continue
        readme = path.read_text(encoding="utf-8")
        updated = apply(readme, render(template, config, name))
        if updated == readme:
            continue
        stale.append(name)
        if not args.check:
            path.write_text(updated, encoding="utf-8")
            print(f"updated {name}")
    if args.check and stale:
        print("footer out of date: " + ", ".join(stale))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
