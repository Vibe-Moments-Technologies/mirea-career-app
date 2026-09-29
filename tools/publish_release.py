#!/usr/bin/env python3
"""
tools/publish_release.py — публикация релиза с артефактами Android и iOS.

Схема из krasava-app, адаптирована под Flutter (APK/AAB + IPA).

Что делает:
  * stable  — создаёт/обновляет релиз по тегу, прикладывает APK, AAB и IPA;
  * beta/rc — то же, но помечает prerelease;
  * dev     — обновляет ОДИН rolling-релиз `preview` (артефакты заменяются,
              релизы не плодятся при каждом push в main).

Релиз-ноты генерируются из коммитов между предыдущим тегом и текущим, если
CHANGELOG.md для версии не найден.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass


def run(cmd: list[str], check: bool = True, capture: bool = True) -> str:
    result = subprocess.run(cmd, text=True, capture_output=capture)
    if check and result.returncode != 0:
        sys.exit(f"command failed: {' '.join(cmd)}\n{result.stderr}")
    return (result.stdout or "").strip()


def gh(*args: str, check: bool = True) -> str:
    return run(["gh", *args], check=check)


def release_notes(version: str, prev_tag: str | None) -> str:
    """Список изменений: из CHANGELOG.md, иначе из коммитов."""
    changelog = Path("CHANGELOG.md")
    if changelog.exists():
        content = changelog.read_text(encoding="utf-8")
        marker = f"## [{version}]"
        if marker in content:
            body = content.split(marker, 1)[1]
            body = body.split("\n## [", 1)[0]
            return f"## {version}\n{body.strip()}"

    if prev_tag:
        commits = run(
            ["git", "log", f"{prev_tag}..HEAD", "--pretty=format:- %s (%h)"], check=False
        )
        if commits:
            return f"Изменения с {prev_tag}:\n\n{commits}"

    return f"Сборка {version}"


def main() -> None:
    p = argparse.ArgumentParser(description="Публикация релиза «Карьера РТУ МИРЭА»")
    p.add_argument("--channel", required=True, choices=["stable", "beta", "rc", "dev"])
    p.add_argument("--version", required=True)
    p.add_argument("--build-number", required=True)
    p.add_argument("--commit-sha", default="")
    p.add_argument("--apk", default=None)
    p.add_argument("--aab", default=None)
    p.add_argument("--ipa", default=None)
    p.add_argument("--prev-tag", default=None)
    p.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    args = p.parse_args()

    assets = [a for a in (args.apk, args.aab, args.ipa) if a and Path(a).exists()]
    if not assets:
        sys.exit("no artifacts found to publish")

    # dev-сборки живут в одном rolling-релизе `preview`:
    # иначе каждый push в main плодил бы релизы
    if args.channel == "dev":
        tag = "preview"
        title = f"Preview {args.version}"
        notes = f"Rolling dev build {args.version} (build {args.build_number})"
        prerelease = True
    else:
        tag = f"v{args.version}"
        title = f"Карьера РТУ МИРЭА {args.version}"
        notes = release_notes(args.version, args.prev_tag)
        prerelease = args.channel != "stable"

    notes += (
        f"\n\n---\n"
        f"**Сборка:** `{args.build_number}`"
        + (f"  \n**Коммит:** `{args.commit_sha}`" if args.commit_sha else "")
        + f"\n**Канал:** `{args.channel}`\n"
    )

    # существует ли релиз с этим тегом
    exists = run(
        ["gh", "release", "view", tag, "--repo", args.repo, "--json", "tagName"],
        check=False,
    )

    if exists:
        print(f"release {tag} exists - uploading assets (replacing)")
        for asset in assets:
            # --clobber: rolling-preview перезаписывает старые файлы,
            # иначе gh откажется загружать одноимённый ассет
            gh("release", "upload", tag, asset, "--clobber", "--repo", args.repo)
        gh(
            "release", "edit", tag,
            "--title", title, "--notes", notes, "--repo", args.repo,
            "--prerelease" if prerelease else "--latest",
        )
    else:
        print(f"creating release {tag}")
        flags = ["--prerelease"] if prerelease else ["--latest"]
        if args.channel == "dev":
            flags = ["--prerelease"]
        gh(
            "release", "create", tag,
            "--title", title, "--notes", notes, "--repo", args.repo,
            *flags,
            *assets,
        )

    url = gh("release", "view", tag, "--repo", args.repo, "--json", "url",
             "--jq", ".url", check=False)
    print(f"\nRelease: {url or tag}")
    print(f"Assets : {', '.join(Path(a).name for a in assets)}")


if __name__ == "__main__":
    main()