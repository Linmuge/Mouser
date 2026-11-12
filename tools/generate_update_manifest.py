#!/usr/bin/env python3
"""Generate Mouser update metadata from release assets."""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sys

# Allow running as `python tools/generate_update_manifest.py` from the repo
# root: put the repo root on sys.path so the `core` package resolves.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from core.update_installer import (
    APP_ID,
    MANIFEST_SCHEMA_VERSION,
    STABLE_CHANNEL,
    build_number_from_version,
    sha256_file,
    verify_update_manifest,
)
from core.updater import DEFAULT_RELEASE_REPO


_ASSET_PLATFORM_KEYS = {
    "Mouser-Windows.zip": "windows-x64",
    "Mouser-macOS.zip": "macos-arm64",
    "Mouser-macOS-intel.zip": "macos-x86_64",
    "Mouser-Linux.zip": "linux-x64",
    "Mouser-Windows-arm64.zip": "windows-arm64",
}


def _native_macos_dmg(asset_dir: Path) -> Path | None:
    candidates = sorted(
        path
        for path in asset_dir.glob("Mouser-*.dmg")
        if "-debug" not in path.stem.lower()
    )
    if len(candidates) > 1:
        names = ", ".join(path.name for path in candidates)
        raise SystemExit(f"Multiple release macOS DMGs found: {names}")
    return candidates[0] if candidates else None


def _version_from_tag(tag: str) -> str:
    return tag[1:] if tag.startswith("v") else tag


def build_payload(args) -> dict:
    asset_dir = Path(args.asset_dir)
    version = _version_from_tag(args.tag)
    tag = f"v{version}"
    if args.tag != tag:
        raise SystemExit(f"Release tag must be {tag}")
    canonical_build = build_number_from_version(version)
    build_number = int(args.build_number or canonical_build)
    if build_number != canonical_build:
        raise SystemExit(
            f"Build number for {version} must be the canonical value {canonical_build}"
        )
    assets = {}
    for name, platform_key in _ASSET_PLATFORM_KEYS.items():
        path = asset_dir / name
        if not path.exists():
            continue
        assets[platform_key] = {
            "name": name,
            "url": f"https://github.com/{args.repo}/releases/download/{tag}/{name}",
            "size": path.stat().st_size,
            "sha256": sha256_file(path),
        }
    if native_dmg := _native_macos_dmg(asset_dir):
        native_asset = {
            "name": native_dmg.name,
            "url": f"https://github.com/{args.repo}/releases/download/{tag}/{native_dmg.name}",
            "size": native_dmg.stat().st_size,
            "sha256": sha256_file(native_dmg),
        }
        assets["macos-arm64"] = native_asset
        assets["macos-x86_64"] = native_asset.copy()
    if not assets:
        raise SystemExit(f"No known Mouser assets found in {asset_dir}")
    expires_days = int(getattr(args, "expires_days", 0) or 0)
    if expires_days < 0:
        raise SystemExit("Expiry days cannot be negative")
    payload = {
        "schema": MANIFEST_SCHEMA_VERSION,
        "app_id": APP_ID,
        "channel": STABLE_CHANNEL,
        "version": version,
        "tag": tag,
        "build_number": build_number,
        "commit": args.commit,
        "release_notes_url": f"https://github.com/{args.repo}/releases/tag/{tag}",
        "assets": assets,
    }
    # Expiry remains available for older consumers when explicitly requested,
    # but new immutable release manifests do not expire by default. Schema v1
    # has no long-term signature whose freshness could safely be renewed.
    if expires_days:
        expires_at = (
            datetime.now(timezone.utc) + timedelta(days=expires_days)
        ).replace(microsecond=0)
        payload["expires_at"] = expires_at.isoformat().replace("+00:00", "Z")
    for platform_key in assets:
        verify_update_manifest(
            payload,
            platform_key=platform_key,
            expected_tag=tag,
            expected_repo=args.repo,
        )
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=DEFAULT_RELEASE_REPO)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--asset-dir", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument(
        "--expires-days",
        default="0",
        help="Legacy advisory expiry. New static manifests default to no expiry.",
    )
    parser.add_argument("--build-number", default="")
    args = parser.parse_args()

    payload = build_payload(args)
    Path(args.output).write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
