#!/usr/bin/env python3
"""
Lyrics resolution and LRC parser for the Quickshell Pill.
Supports local .lrc files (in ~/Music, cache, or track directory) and online LRCLIB sync.
Robustly parses browser/YouTube/Spotify/MPD track formats and video titles.
"""
import json
import os
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

CACHE_DIR = Path.home() / ".cache" / "lyrics"
CACHE_DIR.mkdir(parents=True, exist_ok=True)
MUSIC_DIR = Path.home() / "Music"

GENERIC_ARTISTS = {
    "youtube", "google chrome", "brave", "chromium", "firefox",
    "zen", "zen browser", "vlc", "mpv", "unknown", ""
}

def sanitize_filename(name):
    return re.sub(r'[\\/*?:"<>|]', "", name).strip()

def clean_title(title):
    t = title
    # Remove youtube/video annotations in parens or brackets
    t = re.sub(r'[\(\[](?:official\s+)?(?:music\s+)?(?:video|audio|lyric\s+video|lyrics|visualizer|mv|hd|4k|remastered|live|clip\s+officiel)[^\)\]]*[\)\]]', '', t, flags=re.I)
    t = re.sub(r'\s*\|\s*(?:official\s+)?(?:video|audio|lyrics?|youtube).*$', '', t, flags=re.I)
    t = re.sub(r'\s*-\s*(?:official\s+)?(?:video|audio|lyrics?|youtube|topic).*$', '', t, flags=re.I)
    t = re.sub(r'\s*(?:feat\.|ft\.|featuring)\s+[^(\[\],-]+', '', t, flags=re.I)
    return t.strip(' "\'-–—\t\r\n')

def extract_artist_title(artist, title):
    c_title = clean_title(title)
    art = artist.strip() if artist else ""
    
    # If artist is missing or generic (e.g. from browser or youtube), try splitting from title
    if (not art or art.lower() in GENERIC_ARTISTS) and (' - ' in c_title or ' – ' in c_title or ' — ' in c_title or ' : ' in c_title):
        parts = re.split(r'\s*[-–—:]\s*', c_title, maxsplit=1)
        if len(parts) == 2 and parts[0] and parts[1]:
            return parts[0].strip(' "\''), parts[1].strip(' "\'')
            
    return (art if art.lower() not in GENERIC_ARTISTS else ""), c_title

def parse_lrc(lrc_text):
    lines = []
    # Match [mm:ss.xx] or [mm:ss.xxx] or [mm:ss]
    pattern = re.compile(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\](.*)')
    for line in lrc_text.splitlines():
        line = line.strip()
        if not line:
            continue
        # Check metadata headers
        if re.match(r'^\[(ar|ti|al|by|offset|length):', line, re.IGNORECASE):
            continue
        matches = pattern.findall(line)
        if matches:
            for m in matches:
                mins = int(m[0])
                secs = int(m[1])
                ms_str = m[2] or "0"
                if len(ms_str) == 2:
                    ms = int(ms_str) * 10
                elif len(ms_str) == 1:
                    ms = int(ms_str) * 100
                else:
                    ms = int(ms_str[:3])
                time_sec = mins * 60 + secs + (ms / 1000.0)
                text = m[3].strip()
                if text:
                    lines.append({"time": round(time_sec, 2), "text": text})
    lines.sort(key=lambda x: x["time"])
    return lines

def find_local_lrc(artist, title, album="", file_url=""):
    candidates = []
    
    # 1. Check local file if file_url provided
    if file_url and file_url.startswith("file://"):
        try:
            local_path = Path(urllib.parse.unquote(file_url[7:]))
            if local_path.is_file():
                candidates.append(local_path.with_suffix(".lrc"))
        except Exception:
            pass

    # 2. Check ~/Music directory
    s_artist = sanitize_filename(artist)
    s_title = sanitize_filename(title)
    s_clean_title = sanitize_filename(clean_title(title))

    if MUSIC_DIR.is_dir():
        if s_artist and s_title:
            candidates.append(MUSIC_DIR / f"{s_artist} - {s_title}.lrc")
            candidates.append(MUSIC_DIR / f"{s_artist} - {s_clean_title}.lrc")
            candidates.append(MUSIC_DIR / s_artist / f"{s_title}.lrc")
        if s_title:
            candidates.append(MUSIC_DIR / f"{s_title}.lrc")
            candidates.append(MUSIC_DIR / f"{s_clean_title}.lrc")

    # 3. Check ~/.cache/lyrics
    if s_artist and s_title:
        candidates.append(CACHE_DIR / f"{s_artist} - {s_title}.lrc")
        candidates.append(CACHE_DIR / f"{s_artist} - {s_clean_title}.lrc")
    if s_title:
        candidates.append(CACHE_DIR / f"{s_title}.lrc")
        candidates.append(CACHE_DIR / f"{s_clean_title}.lrc")

    for p in candidates:
        if p and p.is_file():
            try:
                return p.read_text(encoding="utf-8", errors="replace")
            except Exception:
                pass
    return None

def fetch_lrclib(artist, title, album=""):
    headers = {"User-Agent": "Quickshell-Pill/1.0 (Linux)"}
    
    # Strategy 1: Exact /api/get with artist & track
    if artist and title:
        try:
            params = {"artist_name": artist, "track_name": title}
            if album:
                params["album_name"] = album
            url = "https://lrclib.net/api/get?" + urllib.parse.urlencode(params)
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=3) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                if data.get("syncedLyrics"):
                    return data["syncedLyrics"]
        except Exception:
            pass

    # Strategy 2: Search queries with combinations
    queries = []
    if artist and title:
        queries.append(f"{artist} {title}".strip())
    if title:
        queries.append(title.strip())
        
    for q in queries:
        if not q:
            continue
        try:
            url = "https://lrclib.net/api/search?" + urllib.parse.urlencode({"q": q})
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=3) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                if isinstance(data, list):
                    for item in data:
                        if item.get("syncedLyrics"):
                            return item["syncedLyrics"]
        except Exception:
            pass

    return None

def get_lyrics(artist, title, album="", file_url=""):
    if not title:
        return {"has_lyrics": False, "synced": False, "lines": []}

    # Extract actual artist and title if coming from browser / youtube video title
    extracted_artist, extracted_title = extract_artist_title(artist, title)
    
    # Try local search first
    lrc = find_local_lrc(extracted_artist, extracted_title, album, file_url)
    if not lrc and artist != extracted_artist:
        lrc = find_local_lrc(artist, title, album, file_url)
    
    # If not found locally, fetch online from LRCLIB
    if not lrc:
        lrc = fetch_lrclib(extracted_artist, extracted_title, album)
        if not lrc and (artist or title):
            lrc = fetch_lrclib(artist, clean_title(title), album)
            
        if lrc:
            # Save to cache
            s_artist = sanitize_filename(extracted_artist)
            s_title = sanitize_filename(extracted_title)
            cache_file = CACHE_DIR / f"{s_artist} - {s_title}.lrc" if s_artist else CACHE_DIR / f"{s_title}.lrc"
            try:
                cache_file.write_text(lrc, encoding="utf-8")
            except Exception:
                pass

    if not lrc:
        return {"has_lyrics": False, "synced": False, "lines": []}

    lines = parse_lrc(lrc)
    return {
        "has_lyrics": len(lines) > 0,
        "synced": len(lines) > 0,
        "lines": lines,
        "artist": extracted_artist,
        "title": extracted_title
    }

def main():
    if len(sys.argv) < 3:
        print(json.dumps({"has_lyrics": False, "synced": False, "lines": []}))
        return

    artist = sys.argv[1] if len(sys.argv) > 1 else ""
    title = sys.argv[2] if len(sys.argv) > 2 else ""
    album = sys.argv[3] if len(sys.argv) > 3 else ""
    file_url = sys.argv[4] if len(sys.argv) > 4 else ""

    result = get_lyrics(artist, title, album, file_url)
    print(json.dumps(result))

if __name__ == "__main__":
    main()

