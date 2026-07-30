#!/usr/bin/env python3
"""Collect install/usage metrics for Notch So Good into append-only CSVs.

Why this exists: GitHub's traffic API only retains the last 14 days of clone and
view data. Once a day falls out of that window it is gone permanently. Running
this daily preserves the full history in-repo.

Data sources (all public or repo-scoped, no third-party accounts):
  - npm registry download counts       (api.npmjs.org)
  - GitHub release asset downloads     (cumulative, per asset)
  - GitHub traffic clones / views      (rolling 14-day window)
  - GitHub repo stars / forks / watchers

Writes three CSVs under metrics/:
  daily.csv      one row per calendar day, upserted (recent days get revised)
  snapshots.csv  one row per run, cumulative point-in-time counters
  releases.csv   per-release-asset download totals, upserted

Auth: set GITHUB_TOKEN for traffic endpoints (they require push access). Without
it the script still records npm + public repo data and reports what it skipped.
Never fails the build on a single source erroring — partial data beats no data.
"""

import csv
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO = os.environ.get("METRICS_REPO", "deepshal99/notch-so-good")
NPM_PACKAGE = os.environ.get("METRICS_NPM_PACKAGE", "notch-so-good")
TOKEN = os.environ.get("GITHUB_TOKEN") or os.environ.get("METRICS_TOKEN")

METRICS_DIR = Path(__file__).resolve().parent.parent / "metrics"
DAILY_CSV = METRICS_DIR / "daily.csv"
SNAPSHOT_CSV = METRICS_DIR / "snapshots.csv"
RELEASES_CSV = METRICS_DIR / "releases.csv"

DAILY_FIELDS = [
    "date",
    "npm_downloads",
    "clones_total",
    "clones_unique",
    "views_total",
    "views_unique",
]
SNAPSHOT_FIELDS = [
    "captured_at",
    "stars",
    "forks",
    "watchers",
    "open_issues",
    "release_downloads_total",
    "npm_downloads_alltime",
]
RELEASE_FIELDS = ["tag", "asset", "download_count", "published_at", "captured_at"]

# Collected as we go so the run summary can be honest about gaps.
warnings: list[str] = []


def fetch_json(url: str, *, auth: bool = False):
    """GET and parse JSON. Returns None on any failure, recording a warning."""
    req = urllib.request.Request(url, headers={"User-Agent": "notch-so-good-metrics"})
    req.add_header("Accept", "application/vnd.github+json")
    if auth:
        if not TOKEN:
            warnings.append(f"skipped (no token): {url}")
            return None
        req.add_header("Authorization", f"Bearer {TOKEN}")
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = ""
        if e.code == 403:
            # Traffic endpoints need push access; the default GITHUB_TOKEN may lack it.
            detail = " (traffic endpoints require push access — try a PAT as METRICS_TOKEN)"
        warnings.append(f"HTTP {e.code} for {url}{detail}")
    except Exception as e:  # network, JSON, timeout
        warnings.append(f"{type(e).__name__} for {url}: {e}")
    return None


def read_csv(path: Path, key: str) -> dict:
    """Load an existing CSV into a dict keyed by `key`. Empty dict if absent."""
    if not path.exists():
        return {}
    with path.open(newline="", encoding="utf-8") as f:
        return {row[key]: row for row in csv.DictReader(f) if row.get(key)}


def write_csv(path: Path, fields: list, rows: dict, sort_key):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for k in sorted(rows, key=sort_key):
            writer.writerow(rows[k])


def collect_npm_daily(existing: dict):
    """Backfill npm daily downloads.

    npm serves arbitrary historical ranges, so on a fresh checkout we pull from
    package creation; afterwards we only re-fetch a short trailing window (npm
    revises very recent numbers).
    """
    meta = fetch_json(f"https://registry.npmjs.org/{NPM_PACKAGE}")
    created = None
    if meta:
        created = (meta.get("time") or {}).get("created", "")[:10] or None

    today = datetime.now(timezone.utc).date()
    if existing:
        # Re-fetch the last 10 days to pick up npm's late revisions.
        start = today - timedelta(days=10)
    else:
        start = datetime.strptime(created, "%Y-%m-%d").date() if created else today - timedelta(days=365)

    total_alltime = 0
    cursor = start
    # npm caps a single range request at 18 months; chunk to stay well under it.
    while cursor <= today:
        chunk_end = min(cursor + timedelta(days=364), today)
        data = fetch_json(
            f"https://api.npmjs.org/downloads/range/{cursor}:{chunk_end}/{NPM_PACKAGE}"
        )
        if data:
            for point in data.get("downloads", []):
                day = point.get("day")
                if not day:
                    continue
                row = existing.setdefault(day, {"date": day})
                row["npm_downloads"] = point.get("downloads", 0)
        cursor = chunk_end + timedelta(days=1)

    # All-time total is a separate query so it stays correct even on incremental runs.
    if created:
        alltime = fetch_json(
            f"https://api.npmjs.org/downloads/range/{created}:{today}/{NPM_PACKAGE}"
        )
        if alltime:
            total_alltime = sum(p.get("downloads", 0) for p in alltime.get("downloads", []))
    return total_alltime


def collect_traffic(existing: dict):
    """Merge the rolling 14-day clone/view windows into the daily history.

    Recent days are intentionally overwritten rather than skipped: GitHub revises
    same-day and previous-day counts.
    """
    for kind, total_field, unique_field in (
        ("clones", "clones_total", "clones_unique"),
        ("views", "views_total", "views_unique"),
    ):
        data = fetch_json(
            f"https://api.github.com/repos/{REPO}/traffic/{kind}", auth=True
        )
        if not data:
            continue
        for point in data.get(kind, []):
            day = (point.get("timestamp") or "")[:10]
            if not day:
                continue
            row = existing.setdefault(day, {"date": day})
            row[total_field] = point.get("count", 0)
            row[unique_field] = point.get("uniques", 0)


def collect_releases(existing: dict):
    """Upsert per-asset cumulative download counts. Returns the grand total."""
    releases = fetch_json(f"https://api.github.com/repos/{REPO}/releases?per_page=100")
    if not releases:
        return None
    captured = datetime.now(timezone.utc).isoformat(timespec="seconds")
    total = 0
    for rel in releases:
        for asset in rel.get("assets", []):
            count = asset.get("download_count", 0)
            total += count
            key = f"{rel.get('tag_name')}|{asset.get('name')}"
            existing[key] = {
                "tag": rel.get("tag_name"),
                "asset": asset.get("name"),
                "download_count": count,
                "published_at": rel.get("published_at"),
                "captured_at": captured,
            }
    return total


def main() -> int:
    daily = read_csv(DAILY_CSV, "date")

    # releases.csv needs a composite key, so it can't use read_csv's single-column form.
    releases = {}
    if RELEASES_CSV.exists():
        with RELEASES_CSV.open(newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                if row.get("tag") and row.get("asset"):
                    releases[f"{row['tag']}|{row['asset']}"] = row

    npm_alltime = collect_npm_daily(daily)
    collect_traffic(daily)
    release_total = collect_releases(releases)

    repo = fetch_json(f"https://api.github.com/repos/{REPO}") or {}

    # Normalise every daily row so the CSV is rectangular and diffs stay readable.
    for row in daily.values():
        for field in DAILY_FIELDS:
            row.setdefault(field, "")

    write_csv(DAILY_CSV, DAILY_FIELDS, daily, sort_key=lambda d: d)
    write_csv(
        RELEASES_CSV,
        RELEASE_FIELDS,
        releases,
        sort_key=lambda k: (releases[k].get("published_at") or "", k),
    )

    snapshots = {}
    if SNAPSHOT_CSV.exists():
        with SNAPSHOT_CSV.open(newline="", encoding="utf-8") as f:
            snapshots = {r["captured_at"]: r for r in csv.DictReader(f) if r.get("captured_at")}
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    snapshots[now] = {
        "captured_at": now,
        "stars": repo.get("stargazers_count", ""),
        "forks": repo.get("forks_count", ""),
        "watchers": repo.get("subscribers_count", ""),
        "open_issues": repo.get("open_issues_count", ""),
        "release_downloads_total": release_total if release_total is not None else "",
        "npm_downloads_alltime": npm_alltime or "",
    }
    write_csv(SNAPSHOT_CSV, SNAPSHOT_FIELDS, snapshots, sort_key=lambda k: k)

    recent = sorted(daily)[-7:]
    npm_7d = sum(int(daily[d].get("npm_downloads") or 0) for d in recent)
    clones_7d = sum(int(daily[d].get("clones_unique") or 0) for d in recent)

    print(f"Days of history:        {len(daily)}")
    print(f"npm all-time:           {npm_alltime or 'n/a'}")
    print(f"npm last 7d:            {npm_7d}")
    print(f"Unique cloners last 7d: {clones_7d}")
    print(f"Release downloads:      {release_total if release_total is not None else 'n/a'}")
    print(f"Stars:                  {repo.get('stargazers_count', 'n/a')}")

    if warnings:
        print("\nIncomplete sources (data still written for everything else):")
        for w in dict.fromkeys(warnings):
            print(f"  - {w}")

    # Exit 0 regardless: a missing source must not break the daily commit.
    return 0


if __name__ == "__main__":
    sys.exit(main())
