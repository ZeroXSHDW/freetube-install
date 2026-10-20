#!/usr/bin/env python3
"""Update FreeTube's auto-generated "Top Charts" playlists for many genres.

Fetches the iTunes Top-100 genre charts (a reliable, key-free proxy for "most
popular music"), resolves each song to its official YouTube video through
Invidious, and writes one FreeTube playlist per genre plus a manifest that the
menu-bar app reads.

Genres span Pop, Hip-Hop/Rap, Rock, Country, R&B/Soul, Electronic, Dance,
Alternative, Latin, Reggae, Jazz, Classical, Blues, Singer/Songwriter, World,
Soundtrack, plus Russian Rap and Russian Pop.

Run this only while FreeTube is closed. The companion shell wrapper enforces
that. Requires only the Python standard library.
"""
from __future__ import annotations

import json
import pathlib
import random
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

# name, country, iTunes genre id, playlist id
GENRES = [
    ("Pop", "us", 14, "ft-playlist--f57ffd84-a5ea-45d5-8129-b48e24f4d2dc"),
    ("Hip-Hop/Rap", "us", 18, "ft-playlist--b4395627-d6b2-4d65-a296-1836e7aa6da9"),
    ("Rock", "us", 21, "ft-playlist--7a04651f-260f-438d-ae53-0dd4e9d15f74"),
    ("Country", "us", 6, "ft-playlist--04965f80-08ba-41f4-94ca-dbad384ec476"),
    ("R&B/Soul", "us", 15, "ft-playlist--19410a60-d8d8-4b50-8169-dc46547f766f"),
    ("Electronic", "us", 7, "ft-playlist--6d891e90-99a0-4a2f-8a23-b8d711d047f7"),
    ("Dance", "us", 17, "ft-playlist--6369c292-8f69-494c-a32f-de68088c8135"),
    ("Alternative", "us", 20, "ft-playlist--fb4aa356-4156-4804-b17c-156ec57e986c"),
    ("Latin", "us", 12, "ft-playlist--53ffc935-95bf-4c6c-8925-e5b61857eb4a"),
    ("Reggae", "us", 24, "ft-playlist--0d49ae5b-fd6f-41cd-a4dc-88aa88d5e88c"),
    ("Jazz", "us", 11, "ft-playlist--6ee19f2d-4768-42f2-a244-5fc627ea0ec9"),
    ("Classical", "us", 5, "ft-playlist--b52fb133-ce7b-49b3-a540-fd6c885eaab0"),
    ("Blues", "us", 2, "ft-playlist--b607d848-2f2f-4bee-afb1-b0046c41826c"),
    ("Singer/Songwriter", "us", 10, "ft-playlist--65deec75-f2c1-4a2d-95d4-d38f78d42754"),
    ("World", "us", 19, "ft-playlist--9089cade-980f-484b-a9f2-3b3951d68554"),
    ("Soundtrack", "us", 16, "ft-playlist--6a1d1c44-01fb-4410-a152-51de98fdc4d8"),
    ("Russian Rap", "ru", 18, "ft-playlist--e318ffef-84db-4e77-9fd8-ecbd427b6168"),
    ("Russian Pop", "ru", 14, "ft-playlist--c2fbb61e-369d-4403-ae12-f323d965b998"),
]

MANAGED_PREFIX = "Top Charts —"
INSTANCES_URL = "https://api.invidious.io/instances.json?sort_by=health"
MIN_SONGS = 6  # do not overwrite an existing playlist with fewer than this
DEFAULT_LIMIT = 15
RADIO_ID = "ft-playlist--b3f8026b-4773-43a6-9f35-a477dca1b96d"
RADIO_LIMIT = 100
FAVORITES_ID = "favorites"


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


def fetch_chart(country: str, genre_id: int, limit: int) -> list[tuple[str, str]]:
    url = f"https://itunes.apple.com/{country}/rss/topsongs/limit={limit}/genre={genre_id}/explicit=true/json"
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


def is_bad_match(item: dict) -> bool:
    """Heuristics that exclude non-music or mis-resolved results."""
    title = (item.get("title") or "").lower()
    if item.get("liveNow"):
        return True
    if re.search(r"\blive\b|🔴|stream|пресс|конференц|обзор|прохождение", title):
        return True
    return False


def resolve_song(instances: list[str], artist: str, title: str) -> dict | None:
    query = f"{primary_artist(artist)} {clean_title(title)}"
    results = search_invidious(instances, query)
    if not results:
        return None
    candidates = []
    for item in results:
        if is_bad_match(item):
            continue
        score = score_result(item, artist, title)
        if score < 2:  # require a title OR artist match, no random fallbacks
            continue
        candidates.append((score, item.get("viewCount") or 0, item))
    if not candidates:
        return None
    _, _, best = max(candidates, key=lambda c: (c[0], c[1]))
    return {
        "videoId": best.get("videoId"),
        "title": best.get("title") or title,
        "author": best.get("author") or artist,
        "authorId": best.get("authorId"),
        "lengthSeconds": best.get("lengthSeconds") or 0,
        "published": (best.get("published") or 0) * 1000,
    }


def oembed_available(video_id: str) -> bool:
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


def build_genre(instances: list[str], name: str, country: str, genre_id: int, limit: int) -> list[dict]:
    songs = fetch_chart(country, genre_id, limit)
    with ThreadPoolExecutor(max_workers=4) as pool:
        resolved = list(pool.map(lambda s: resolve_song(instances, s[0], s[1]), songs))

    video_ids = [r["videoId"] for r in resolved if r and r["videoId"]]
    with ThreadPoolExecutor(max_workers=8) as pool:
        flags = list(pool.map(oembed_available, video_ids))

    now = int(time.time() * 1000)
    videos: list[dict] = []
    seen: set[str] = set()
    flag_iter = iter(flags)
    for r in resolved:
        if not r or not r["videoId"]:
            continue
        ok = next(flag_iter)
        vid = r["videoId"]
        if not ok or vid in seen:
            continue
        seen.add(vid)
        videos.append(
            {
                "videoId": vid,
                "title": r["title"],
                "author": r["author"],
                "authorId": r["authorId"],
                "lengthSeconds": r["lengthSeconds"],
                "published": r["published"],
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


def flush_favorites(db_path: pathlib.Path, favorites_path: pathlib.Path) -> int:
    """Merge favorites.json into FreeTube's built-in 'Favorites' playlist."""
    if not favorites_path.is_file():
        return 0
    try:
        favs = json.loads(favorites_path.read_text(encoding="utf-8"))
    except Exception:
        return 0
    if not isinstance(favs, list) or not favs:
        return 0

    docs, order = load_playlists(db_path)
    now = int(time.time() * 1000)
    fav_doc = docs.get(FAVORITES_ID)
    if fav_doc is None:
        fav_doc = {
            "playlistName": "Favorites",
            "protected": False,
            "description": "Your favorite videos",
            "videos": [],
            "_id": FAVORITES_ID,
            "createdAt": now,
        }
        docs[FAVORITES_ID] = fav_doc
        order.append(FAVORITES_ID)

    existing = {v.get("videoId"): v for v in fav_doc.get("videos", []) if v.get("videoId")}
    added = 0
    for fav in favs:
        vid = fav.get("videoId")
        if not vid or vid in existing:
            continue
        existing[vid] = {
            "videoId": vid,
            "title": fav.get("title", ""),
            "author": fav.get("author", ""),
            "authorId": fav.get("authorId"),
            "lengthSeconds": fav.get("lengthSeconds", 0),
            "published": fav.get("published", 0),
            "timeAdded": now,
            "playlistItemId": str(uuid.uuid4()),
            "type": "video",
        }
        added += 1

    fav_doc["videos"] = list(existing.values())
    fav_doc["lastUpdatedAt"] = now
    write_playlists(db_path, docs, order)
    return added


def main() -> int:
    args = [a for a in sys.argv[1:]]
    db_arg = args[0] if args and not args[0].startswith("--") else ""
    dry_run = "--dry-run" in args
    limit = DEFAULT_LIMIT
    only = None
    if "--limit" in args:
        limit = int(args[args.index("--limit") + 1])
    if "--only" in args:
        only = {n.strip().lower() for n in args[args.index("--only") + 1].split(",")}

    db_path = (
        pathlib.Path(db_arg).expanduser()
        if db_arg
        else pathlib.Path.home() / "Library/Application Support/FreeTube/playlists.db"
    )
    manifest_path = db_path.parent / "top-charts.json"

    # Rebuild the manifest from existing playlists without any network access.
    if "--manifest-only" in args:
        docs, _ = load_playlists(db_path)
        manifest = []
        for name, _country, _gid, pid in GENRES:
            doc = docs.get(pid)
            if not doc:
                continue
            ids = [v.get("videoId") for v in doc.get("videos", []) if v.get("videoId")]
            if not ids:
                continue
            manifest.append({"name": name, "playlistId": pid, "firstVideoId": ids[0], "videoIds": ids})
        radio_doc = docs.get(RADIO_ID)
        if radio_doc:
            rids = [v.get("videoId") for v in radio_doc.get("videos", []) if v.get("videoId")]
            if rids:
                manifest.append({"name": "Radio Mix", "playlistId": RADIO_ID, "firstVideoId": rids[0], "videoIds": rids})
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Rebuilt manifest ({len(manifest)} genres) from {db_path}")
        return 0

    # Merge favorites.json into FreeTube's 'Favorites' playlist without network access.
    if "--favorites-only" in args:
        fav_path = db_path.parent / "favorites.json"
        added = flush_favorites(db_path, fav_path)
        print(f"Flushed favorites into FreeTube ({added} new).")
        return 0

    genres = [g for g in GENRES if only is None or g[0].lower() in only]

    print("Fetching Invidious instances…")
    instances = get_instances()
    print("Instances:", instances)

    docs, order = load_playlists(db_path)
    now = int(time.time() * 1000)
    refreshed = time.strftime("%Y-%m-%d %H:%M")

    managed_ids = {g[3] for g in genres} | {RADIO_ID}
    results = []
    for name, country, genre_id, pid in genres:
        print(f"\n== {name} ==")
        videos = build_genre(instances, name, country, genre_id, limit)
        results.append((name, pid, videos))
        print(f"   resolved {len(videos)} videos")

    # Build a cross-genre "Radio Mix" from everything resolved this run.
    pool: list[dict] = []
    seen_radio: set[str] = set()
    for _name, _pid, videos in results:
        for video in videos:
            if video["videoId"] not in seen_radio:
                seen_radio.add(video["videoId"])
                pool.append(video)
    random.shuffle(pool)
    radio_videos = pool[:RADIO_LIMIT]
    if len(radio_videos) >= MIN_SONGS:
        results.append(("Radio Mix", RADIO_ID, radio_videos))
        print(f"\n== Radio Mix ==\n   {len(radio_videos)} tracks across genres")

    manifest = []
    for name, pid, videos in results:
        if len(videos) >= MIN_SONGS:
            doc = {
                "_id": pid,
                "playlistName": f"{MANAGED_PREFIX} {name}",
                "protected": False,
                "description": f"Auto-updated top {name} (iTunes Top 100). Refreshed {refreshed}.",
                "videos": videos,
                "createdAt": docs.get(pid, {}).get("createdAt", now),
                "lastUpdatedAt": now,
            }
            existing = docs.get(pid)
            if existing and existing.get("lastPlayedAt"):
                doc["lastPlayedAt"] = existing["lastPlayedAt"]
            docs[pid] = doc
            if pid not in order:
                order.append(pid)
            manifest.append({
                "name": name,
                "playlistId": pid,
                "firstVideoId": videos[0]["videoId"],
                "videoIds": [v["videoId"] for v in videos],
            })
        else:
            print(f"WARN  {name}: only {len(videos)} songs resolved (< {MIN_SONGS}); keeping existing.")

    # Remove stale managed playlists (old "Top Charts —" not in the current set).
    for doc_id in list(order):
        doc = docs[doc_id]
        if doc.get("playlistName", "").startswith(MANAGED_PREFIX) and doc_id not in managed_ids:
            order.remove(doc_id)
            del docs[doc_id]

    if dry_run:
        print(f"\nDry run: would write {len(order)} playlists and manifest with {len(manifest)} genres.")
        return 0

    write_playlists(db_path, docs, order)
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    fav_path = db_path.parent / "favorites.json"
    fav_added = flush_favorites(db_path, fav_path)
    print(f"\nWrote {len(order)} playlist records to {db_path}")
    print(f"Wrote manifest ({len(manifest)} genres) to {manifest_path}")
    if fav_added:
        print(f"Merged {fav_added} favorites into FreeTube's Favorites playlist.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
