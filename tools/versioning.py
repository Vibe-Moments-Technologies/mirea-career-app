#!/usr/bin/env python3
"""
tools/versioning.py — единый источник версии для всех сборок.

Схема взята из krasava-app и адаптирована под Flutter (один проект, не KMP).

Каналы:
  stable    тег v26.10 / v26.10.1          → версия 26.10 / 26.10.1
  beta|rc   тег v26.10-beta.1 / -rc.1      → 26.10-beta.1 (prerelease)
  dev       push в main                    → {RELEASE_VERSION}-dev.N (rolling preview)
  contrib   ручная сборка ветки            → {RELEASE_VERSION}-contrib.N

Числовой BUILD_NUMBER (versionCode / CFBundleVersion) = epoch-секунды,
вычисляется ОДИН раз в resolve-джобе. Остальные джобы обязаны брать готовое
число через --build-id: иначе APK и IPA получат разные номера, и свежая
сборка не встанет поверх старой на устройстве тестировщика.

Почему epoch, а не github.run_id: run_id (~34e9) не влезает в Int32, а это
жёсткий потолок Android versionCode (2147483647). Epoch-секунды влезают
с запасом до 2038 года.

Версия в репозитории живёт только в app/pubspec.yaml (version:). Полные
версии с суффиксами CI подставляет сам и не коммитит.

Команды:
  resolve   вычислить версию и записать в $GITHUB_OUTPUT
  prepare   resolve + правка pubspec.yaml (и Info.plist для iOS)
  show      показать версию (для локальной сборки)
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# Windows-консоль по умолчанию cp1251: любой не-ASCII символ в выводе
# роняет скрипт с UnicodeEncodeError (а в CI шаг просто падает).
# Поэтому весь вывод — только ASCII (латиница/цифры/пунктуация).
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

PUBSPEC = "app/pubspec.yaml"
PLIST = "app/ios/Runner/Info.plist"

# v26.10 | v26.10.1 | v26.10-beta.1 | v26.10-rc.2
TAG_RE = re.compile(r"^v(\d+\.\d+(?:\.\d+)?)(?:-(beta|rc)\.(\d+))?$")

# Android versionCode — Int32, жёсткий потолок
MAX_BUILD_ID = 2_147_483_647


def read_release_version() -> str:
    """Линия разработки из pubspec.yaml: '0.1.0+1' → '0.1.0'."""
    content = Path(PUBSPEC).read_text(encoding="utf-8")
    m = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)", content, re.M)
    if not m:
        sys.exit(f"no version found in {PUBSPEC} (expected a 'version: X.Y.Z+N' line)")
    return m.group(1)


def short_sha() -> str:
    try:
        return subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], text=True).strip()
    except Exception:
        sha = os.environ.get("GITHUB_SHA", "local")
        return sha[:8] if sha else "local"


def compute_build_id(build_time: str | None) -> int:
    """BUILD_NUMBER из ISO8601 или текущего времени.

    Вызывается ТОЛЬКО в resolve-джобе — один момент времени на весь запуск.
    github.run_started_at в выражениях workflow рендерится пустым, поэтому
    передавать его бессмысленно: каждая джоба подставила бы своё «сейчас».
    """
    if build_time:
        dt = datetime.fromisoformat(build_time.replace("Z", "+00:00"))
        bid = int(dt.timestamp())
    else:
        bid = int(datetime.now(timezone.utc).timestamp())
    if bid > MAX_BUILD_ID:
        sys.exit(f"build id {bid} is over Int32 max ({MAX_BUILD_ID}) - change the scheme")
    return bid


def next_dev_number(prev_version: str | None, release_version: str) -> int:
    """Номер dev-сборки текущей линии: '0.1.0-dev.17' → 18, смена линии → 1.

    prev_version — имя последнего ОПУБЛИКОВАННОГО preview-релиза, не
    github.run_number: отменённые прогоны номер не съедают.
    """
    m = prev_version and re.search(r"(\d+\.\d+\.\d+)-dev\.(\d+)", prev_version)
    if m and m.group(1) == release_version:
        return int(m.group(2)) + 1
    return 1


def resolve(channel: str, tag: str | None, run_number: str | None,
            build_id: int, prev_version: str | None) -> dict:
    version = ""
    if tag:
        m = TAG_RE.match(tag.strip())
        if not m:
            sys.exit(
                f"bad tag '{tag}'. Expected v26.10, v26.10.1, "
                f"v26.10-beta.1 or v26.10-rc.1"
            )
        version = m.group(1)
        channel = m.group(2) or "stable"
        if m.group(2):
            version += f"-{m.group(2)}.{m.group(3)}"
    elif channel == "dev":
        version = f"{read_release_version()}-dev.{next_dev_number(prev_version, read_release_version())}"
    elif channel == "contrib":
        version = f"{read_release_version()}-contrib.{run_number or '0'}"
    else:
        sys.exit("channel stable/beta/rc requires --tag; dev/contrib require --channel")

    return {
        "version": version,
        "channel": channel,
        "prerelease": "true" if channel != "stable" else "false",
        "build_id": str(build_id),
        "commit_sha": short_sha(),
        "prev_version": prev_version or "",
    }


def numeric_core(version: str) -> str:
    """26.10-dev.151 → 26.10. iOS для CFBundleShortVersionString хочет числовую базу."""
    return version.split("+")[0].split("-")[0]


def patch_pubspec(info: dict) -> None:
    """Полная версия с суффиксом + номер сборки — только во время CI-сборки.

    Flutter читает отсюда и versionName, и versionCode
    ('version: 26.10-dev.3+1759000000'). В репозитории остаётся чистая линия.
    """
    path = Path(PUBSPEC)
    content = path.read_text(encoding="utf-8")
    content = re.sub(
        r"^version:\s*.*$",
        f'version: {info["version"]}+{info["build_id"]}',
        content,
        count=1,
        flags=re.M,
    )
    path.write_text(content, encoding="utf-8")
    print(f"patched {PUBSPEC} -> {info['version']}+{info['build_id']}")


def patch_plist(info: dict) -> None:
    """Числовой код сборки в Info.plist.

    Flutter подставляет CFBundleShortVersionString/CFBundleVersion только при
    генерации проекта. Если Info.plist уже содержит литералы, iOS покажет
    зашитую версию — правим явно.
    """
    path = Path(PLIST)
    if not path.exists():
        print(f"{PLIST} not found - skipping")
        return
    content = path.read_text(encoding="utf-8")
    changed = False

    if re.search(r"<key>CFBundleShortVersionString</key>\s*<string>[^<]+</string>", content):
        content = re.sub(
            r"(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)",
            rf"\g<1>{numeric_core(info['version'])}\g<2>",
            content,
        )
        changed = True

    if re.search(r"<key>CFBundleVersion</key>\s*<string>[^<]*</string>", content):
        content = re.sub(
            r"(<key>CFBundleVersion</key>\s*<string>)[^<]*(</string>)",
            rf"\g<1>{info['build_id']}\g<2>",
            content,
        )
        changed = True

    if changed:
        path.write_text(content, encoding="utf-8")
        print(f"patched {PLIST}")
    else:
        print(f"{PLIST}: Flutter substitutes these itself - leaving alone")


def emit(info: dict) -> None:
    out_file = os.environ.get("GITHUB_OUTPUT")
    if out_file:
        with open(out_file, "a", encoding="utf-8") as f:
            for k, v in info.items():
                f.write(f"{k}={v}\n")
    print("=" * 42)
    print(f"  VERSION  : {info['version']}")
    print(f"  CHANNEL  : {info['channel']}")
    print(f"  BUILD    : {info['build_id']}")
    print(f"  COMMIT   : {info['commit_sha']}")
    print("=" * 42)


def main() -> None:
    p = argparse.ArgumentParser(description="Версионирование сборок «Карьера РТИ МИРЭА»")
    p.add_argument("command", choices=["resolve", "prepare", "show"])
    p.add_argument("--channel", default="stable")
    p.add_argument("--tag", default=None)
    p.add_argument("--run-number", default=None)
    p.add_argument("--build-id", type=int, default=None)
    p.add_argument("--build-time", default=None)
    p.add_argument("--prev-version", default=None)
    args = p.parse_args()

    if args.command == "show":
        print(read_release_version())
        return

    build_id = args.build_id if args.build_id is not None else compute_build_id(args.build_time)
    info = resolve(args.channel, args.tag, args.run_number, build_id, args.prev_version)

    if args.command == "prepare":
        patch_pubspec(info)
        patch_plist(info)
    emit(info)


if __name__ == "__main__":
    main()