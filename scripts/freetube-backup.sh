#!/usr/bin/env bash
# freetube-backup — back up FreeTube's playlists, settings, favorites, watch-later,
# and history to a portable JSON bundle (or to freetube-configs-main).
#
# Usage: freetube-backup.sh [--to DIR] [--from CONFIG_DIR] [--no-git]
set -uo pipefail

CONFIG_DIR="${FREETUBE_CONFIG_DIR:-$HOME/Downloads/freetube-configs-main}"
DEST=""
NO_GIT=0

while (($#)); do
  case "$1" in
    --to) DEST="$2"; shift 2 ;;
    --from) CONFIG_DIR="$2"; shift 2 ;;
    --no-git) NO_GIT=1; shift ;;
    -h|--help)
      echo "Usage: freetube-backup.sh [--to DIR] [--from DIR] [--no-git]"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

SUPPORT="$HOME/Library/Application Support/FreeTube"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_NAME="freetube-backup-$TIMESTAMP"

if [[ -z "$DEST" ]]; then
  DEST="$CONFIG_DIR/config"
  if [[ ! -d "$DEST" ]]; then
    echo "Config dir $DEST not found; creating it." >&2
    mkdir -p "$DEST"
  fi
fi
mkdir -p "$DEST"

echo "Backing up FreeTube to $DEST/$BACKUP_NAME…"

# --- Export playlists.db to a portable JSON bundle ---
PLAYLIST_BUNDLE="$DEST/$BACKUP_NAME-playlists.json"
python3 - "$SUPPORT/playlists.db" "$PLAYLIST_BUNDLE" <<'PY'
import json, pathlib, sys
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
docs, order = {}, []
if src.is_file():
    for line in src.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line: continue
        try: d = json.loads(line)
        except json.JSONDecodeError: continue
        i = d.get("_id")
        if d.get("$$deleted"):
            docs.pop(i, None)
            if i in order: order.remove(i)
            continue
        if i not in order: order.append(i)
        docs[i] = d
bundle = {"exported_at": __import__("time").time(), "playlists": []}
for i in order:
    d = docs[i]
    bundle["playlists"].append({
        "id": i,
        "name": d.get("playlistName", ""),
        "protected": d.get("protected", False),
        "description": d.get("description", ""),
        "videos": d.get("videos", []),
        "createdAt": d.get("createdAt", 0),
        "lastUpdatedAt": d.get("lastUpdatedAt", 0),
        "lastPlayedAt": d.get("lastPlayedAt", 0),
    })
dst.write_text(json.dumps(bundle, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"  Exported {len(bundle['playlists'])} playlists to {dst}")
PY

# --- Copy settings, favorites, watch-later, last-genre, top-charts manifest ---
for f in settings.db favorites.json watchLater.json last-genre.json top-charts.json; do
  if [[ -f "$SUPPORT/$f" ]]; then
    cp "$SUPPORT/$f" "$DEST/$BACKUP_NAME-$f"
    echo "  Copied $f"
  fi
done

# --- Copy history.db ---
if [[ -f "$SUPPORT/history.db" ]]; then
  cp "$SUPPORT/history.db" "$DEST/$BACKUP_NAME-history.db"
  echo "  Copied history.db"
fi

# --- Write a manifest ---
MANIFEST="$DEST/$BACKUP_NAME-manifest.json"
cat > "$MANIFEST" <<EOF
{
  "exported_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "freely_tube_version": "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$HOME/Applications/FreeTube.app/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "/Applications/FreeTube.app/Contents/Info.plist" 2>/dev/null || echo "unknown")",
  "files": [
    "$BACKUP_NAME-playlists.json",
    $(for f in settings.db favorites.json watchLater.json last-genre.json top-charts.json history.db; do
      [[ -f "$DEST/$BACKUP_NAME-$f" ]] && printf '"%s",\n' "$BACKUP_NAME-$f"
    done | sed '$ s/,$//')
  ]
}
EOF
echo "  Wrote manifest $MANIFEST"

# --- Commit to config repo if it's a git repo ---
if ((!NO_GIT)) && [[ -d "$CONFIG_DIR/.git" ]]; then
  echo "Committing to git repo at $CONFIG_DIR…"
  (cd "$CONFIG_DIR" && git add config/ && git -c user.name="${GIT_AUTHOR_NAME:-FreeTube Backup}" -c user.email="${GIT_AUTHOR_EMAIL:-freetube@localhost}" commit -m "Backup $BACKUP_NAME" 2>/dev/null || true)
  echo "  Commit done (or nothing to commit)."
fi

echo "Backup complete: $DEST/$BACKUP_NAME-*"