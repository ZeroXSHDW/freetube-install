#!/usr/bin/env python3
"""Update FreeTube's auto-generated "Top Charts" playlists.

Fetches the iTunes Top-100 genre charts (a reliable, key-free proxy for "most
popular music"), resolves each song to its official YouTube video through
Invidious, and writes three playlists into FreeTube's playlists.db:

  - Top Charts — English Rap   (US, Hip-Hop/Rap)
  - Top Charts — Russian Rap   (RU, Hip-Hop/Rap)
  - Top Charts — Spanish Latin (US, Latino)

Run this only while FreeTube is closed. The companion shell wrapper enforces
that and relaunches FreeTube afterwards.

Requires only the Python standard library.
"""
from __future__ import annotations

import json
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

CHARTS = [
    {
        "playlist_id": "ft-playlist--064ac4d6-c3ae-474e-8149-6358d4ef606d",
        "name": "Top Charts — English Rap",
        "description": "Auto-updated top English rap/hip-hop (iTunes Top 100: Hip-Hop/Rap, US).",
        "url": "https://itunes.apple.com/us/rss/topsongs/limit=25/genre=18/explicit=true/json",
        "limit": 20,
    },
    {
        "playlist_id": "ft-playlist--c2066a73-7aa0-4de8-994c-cb194f8b0317",
        "name": "Top Charts — Russian Rap",
        "description": "Auto-updated top Russian rap/hip-hop (iTunes Top 100: Hip-Hop/Rap, RU).",
        "url": "https://itunes.apple.com/ru/rss/topsongs/limit=25/genre=18/explicit=true/json",
        "limit": 20,
    },
    {
        "playlist_id": "ft-playlist--2dc1c2ca-ce8f-46aa-8b5d-dc85dab276e9",
        "name": "Top Charts — Spanish Latin",
        "description": "Auto-updated top Spanish-language Latin/urban (iTunes Top 100: Latino, US).",
        "url": "https://itunes.apple.com/us/rss/topsongs/limit=25/genre=12/explicit=true/json",
        "limit": 20,
    },
]

INSTANCES_URL = "https://api.invidious.io/instances.json?sort_by=health"
MIN_SONGS = 8  # do not overwrite an existing playlist with fewer than this


def http_text(url: str, timeout: int = 25) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", "replace")


def http_json(url: str, timeout: int = 25):
    return json.loads(http_text(url, timeout))


def get_instances() -> list[str]:
    try:
        data = http_json(INSTANCES_URL, timeout=20)
    except Exception:
        return ["https://invidious.f5.si"]
    instances = []
    for host, info in data:
        if info.get("api") and "onion" not in host and "i2p" not in host:
            uri = (info.get("uri") or "").rstrip("/")
            if uri.startswith("http"):
                instances.append(uri)
    return instances[:5] or ["https://invidious.f5.si"]


def fetch_chart(url: str) -> list[tuple[str, str]]:
    data = http_json(url)
    entries = data.get("feed", {}).get("entry", [])
    songs = []
    for entry in entries:
        try:
            artist = entry["im:artist"]["label"]
            name = entry["im:name"]["label"]
        except (KeyError, TypeError):
            continue
        songs.append((artist, name))
    return songs


def primary_artist(artist: str) -> str:
    return re.split(r"\s*(?:&|,|feat\.?|ft\.?|with|и|,\s*)\s*", artist, maxsplit=1)[0].strip()


def clean_title(title: str) -> str:
    return re.sub(r"\s*\((feat|ft|with)[^)]*\).*$", "", title, flags=re.IGNORECASE).strip()


def search_invidious(instances: list[str], query: str):
    for instance in instances:
        try:
            url = f"{instance}/api/v1/search?q={urllib.parse.quote(query)}&type=video"
            result = http_json(url, timeout=25)
            if isinstance(result, list):
                return result
        except Exception:
            continue
    return []


def score_result(item: dict, artist: str, title: str) -> int:
    video_title = (item.get("title") or "").lower()
    video_author = (item.get("author") or "").lower()
    length = item.get("lengthSeconds") or 0

    score = 0
    core = clean_title(title).lower()
    if core and core in video_title:
        score += 2
    primary = primary_artist(artist).lower()
    if primary and primary in video_author.replace("- topic", ""):
        score += 2
    if re.search(r"\((official|audio|video|lyrics|visualizer)", video_title):
        score += 1
    if 60 <= length <= 1200:
        score += 1
    return score


def resolve_song(instances: list[str], artist: str, title: str) -> dict | None:
    query = f"{primary_artist(artist)} {clean_title(title)}"
    results = search_invidious(instances, query)
    if not results:
        return None
    best = max(results, key=lambda item: score_result(item, artist, title))
    if best is None:
        return None
    return {
        "videoId": best.get("videoId"),
        "title": best.get("title") or title,
        "author": best.get("author") or artist,
        "authorId": best.get("authorId"),
        "lengthSeconds": best.get("lengthSeconds") or 0,
        "published": (best.get("published") or 0) * 1000,
    }


def oembed_available(video_id: str) -> bool:
    """Return False only when YouTube reports the video is removed (404)."""
    url = (
        "https://www.youtube.com/oembed?"
        + urllib.parse.urlencode({"url": f"https://www.youtube.com/watch?v={video_id}", "format": "json"})
    )
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=15):
            return True
    except urllib.error.HTTPError as exc:
        return exc.code != 404
    except Exception:
        return True


def build_chart(instances: list[str], chart: dict) -> list[dict]:
    songs = fetch_chart(chart["url"])[: chart["limit"]]
    resolved = []
    for artist, title in songs:
        item = resolve_song(instances, artist, title)
        if item and item["videoId"]:
            resolved.append((item, artist, title))

    # Drop removed videos and duplicates.
    video_ids = [r[0]["videoId"] for r in resolved]
    with ThreadPoolExecutor(max_workers=8) as pool:
        flags = list(pool.map(oembed_available, video_ids))

    now = int(time.time() * 1000)
    videos: list[dict] = []
    seen: set[str] = set()
    for (item, artist, title), ok in zip(resolved, flags):
        vid = item["videoId"]
        if not ok or vid in seen:
            continue
        seen.add(vid)
        videos.append(
            {
                "videoId": vid,
                "title": item["title"],
                "author": item["author"],
                "authorId": item["authorId"],
                "lengthSeconds": item["lengthSeconds"],
                "published": item["published"],
                "timeAdded": now,
                "playlistItemId": str(uuid.uuid4()),
                "type": "video",
            }
        )
    return videos


def load_playlists(path: pathlib.Path) -> tuple[dict[str, dict], list[str]]:
    docs: dict[str, dict] = {}
    order: list[str] = []
    if path.is_file():
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line:
                continue
            doc = json.loads(line)
            doc_id = doc.get("_id")
            if doc.get("$$deleted"):
                if doc_id in docs:
                    del docs[doc_id]
                    order.remove(doc_id)
                continue
            if doc_id not in docs:
                order.append(doc_id)
            docs[doc_id] = doc
    return docs, order


def write_playlists(path: pathlib.Path, docs: dict[str, dict], order: list[str]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for doc_id in order:
            handle.write(json.dumps(docs[doc_id], ensure_ascii=False, separators=(",", ":")) + "\n")


def main() -> int:
    db_arg = sys.argv[1] if len(sys.argv) > 1 else ""
    dry_run = "--dry-run" in sys.argv
    db_path = (
        pathlib.Path(db_arg).expanduser()
        if db_arg and not db_arg.startswith("--")
        else pathlib.Path.home() / "Library/Application Support/FreeTube/playlists.db"
    )

    print("Fetching Invidious instances…")
    instances = get_instances()
    print("Instances:", instances)

    docs, order = load_playlists(db_path)
    now = int(time.time() * 1000)
    refreshed = time.strftime("%Y-%m-%d %H:%M")

    results = []
    for chart in CHARTS:
        print(f"\n== {chart['name']} ==")
        videos = build_chart(instances, chart)
        results.append((chart, videos))
        for video in videos:
            print(f"   {video['videoId']}  {video['author']} - {video['title'][:55]}")
        print(f"   resolved {len(videos)} videos")

    for chart, videos in results:
        if len(videos) < MIN_SONGS:
            print(
                f"WARN  {chart['name']}: only {len(videos)} songs resolved (< {MIN_SONGS}); "
                "keeping existing playlist."
            )
            continue

        doc_id = chart["playlist_id"]
        existing = docs.get(doc_id)
        doc = {
            "_id": doc_id,
            "playlistName": chart["name"],
            "protected": False,
            "description": f"{chart['description']} Refreshed {refreshed}.",
            "videos": videos,
            "createdAt": (existing or {}).get("createdAt", now),
            "lastUpdatedAt": now,
        }
        if existing and existing.get("lastPlayedAt"):
            doc["lastPlayedAt"] = existing["lastPlayedAt"]
        if doc_id not in docs:
            order.append(doc_id)
        docs[doc_id] = doc

    if dry_run:
        print("\nDry run: playlists.db not modified.")
        return 0

    write_playlists(db_path, docs, order)
    print(f"\nWrote {len(order)} playlist records to {db_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
