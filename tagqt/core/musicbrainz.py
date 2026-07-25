import musicbrainzngs
import re
import unicodedata
import time
import requests
import logging
logger = logging.getLogger(__name__)

musicbrainzngs.set_useragent("TagQt", "1.0", "https://github.com/example/tagqt")
musicbrainzngs.set_rate_limit(limit_or_interval=1.0, new_requests=1)

class MusicBrainzClient:
    """Queries MusicBrainz for release, artist, and genre metadata."""
    @staticmethod
    def normalize_title(title):
        if not title:
            return ""
        normalized = unicodedata.normalize('NFKD', title)
        normalized = normalized.encode('ascii', 'ignore').decode('ascii')
        normalized = re.sub(r'\s*\([^)]*\)\s*$', '', normalized)
        normalized = re.sub(r'\s*\[[^\]]*\]\s*$', '', normalized)
        normalized = re.sub(r"[''`]", "", normalized)
        normalized = re.sub(r'[^\w\s]', '', normalized)
        normalized = ' '.join(normalized.lower().split())
        return normalized
    
    @classmethod
    def titles_match(cls, title1, title2):
        if not title1 or not title2:
            return False
        n1 = cls.normalize_title(title1)
        n2 = cls.normalize_title(title2)
        if n1 == n2:
            return True
        if n1 in n2 or n2 in n1:
            return True
        return False

    @classmethod
    def _retry(cls, func, max_retries=3):
        for attempt in range(max_retries):
            try:
                return func()
            except (musicbrainzngs.NetworkError, requests.exceptions.RequestException, OSError) as e:
                if attempt < max_retries - 1:
                    time.sleep(2 ** attempt)
                    continue
                logger.error(f"MusicBrainz network error after {max_retries} retries: {e}")
                return None
            except musicbrainzngs.MusicBrainzError as e:
                logger.error(f"MusicBrainz API error: {e}")
                return None
        return None
    
    @classmethod
    def search_release(cls, artist, album, track_title=None):
        if not artist and not album:
            return None
        
        def do_search():
            return musicbrainzngs.search_releases(
                artist=artist,
                release=album,
                limit=10
            )
        
        data = cls._retry(do_search)
        if not data:
            return None
            
        releases = data.get("release-list", [])
        if not releases:
            return None
        
        official = [r for r in releases if r.get("status") == "Official"]
        best = official[0] if official else releases[0]
        
        release_id = best.get("id")
        
        result = {
            "id": release_id,
            "title": best.get("title"),
            "date": best.get("date", ""),
            "country": best.get("country", ""),
            "status": best.get("status", ""),
            "artist": "",
            "genres": [],
            "disc_count": 1,
            "track_disc": None,
            "track_position": None,
            "track_count": None,
            "release_group_id": best.get("release-group", {}).get("id") if best.get("release-group") else None
        }
        
        if result["date"]:
            result["year"] = result["date"][:4]
        
        artist_credit = best.get("artist-credit", [])
        if artist_credit:
            first = artist_credit[0]
            if isinstance(first, dict):
                result["artist"] = first.get("name", "") or first.get("artist", {}).get("name", "")
                result["artist_id"] = first.get("artist", {}).get("id")
        
        tags = best.get("tag-list", [])
        if tags:
            sorted_tags = sorted(tags, key=lambda x: int(x.get("count", 0)), reverse=True)
            result["genres"] = [t.get("name", "") for t in sorted_tags[:3]]
        
        if not result["genres"] and result.get("release_group_id"):
            rg_genres = cls.lookup_release_group(result["release_group_id"])
            if rg_genres:
                result["genres"] = rg_genres
        
        if not result["genres"] and result.get("artist_id"):
            artist_genres = cls.lookup_artist(result["artist_id"])
            if artist_genres:
                result["genres"] = artist_genres
        
        return result
    
    @classmethod
    def lookup_release(cls, release_id, track_title=None):
        if not release_id:
            return None
            
        def do_lookup():
            return musicbrainzngs.get_release_by_id(
                release_id,
                includes=["recordings", "media", "tags", "release-groups"]
            )
        
        data = cls._retry(do_lookup)
        if not data:
            return None
            
        release = data.get("release", {})
        
        result = {
            "genres": [],
            "disc_count": 1,
            "track_disc": None,
            "track_position": None,
            "track_count": None,
            "release_group_id": release.get("release-group", {}).get("id") if release.get("release-group") else None
        }
        
        genres = release.get("genre-list", [])
        if genres:
            sorted_genres = sorted(genres, key=lambda x: int(x.get("count", 0)), reverse=True)
            result["genres"] = [g.get("name", "") for g in sorted_genres[:3]]
        
        media = release.get("medium-list", [])
        result["disc_count"] = len(media)
        
        if track_title and media:
            for disc_num, disc in enumerate(media, 1):
                tracks = disc.get("track-list", [])
                for track in tracks:
                    recording = track.get("recording", {})
                    rec_title = recording.get("title", "")
                    if cls.titles_match(track_title, rec_title):
                        result["track_disc"] = disc_num
                        result["track_position"] = int(track.get("position", 0)) if track.get("position") else None
                        result["track_count"] = len(tracks)
                        
                        rec_genres = recording.get("genre-list", [])
                        if rec_genres:
                            sorted_rec = sorted(rec_genres, key=lambda x: int(x.get("count", 0)), reverse=True)
                            result["genres"] = [g.get("name", "") for g in sorted_rec[:3]]
                        
                        break
                if result["track_disc"]:
                    break
        
        return result

    @classmethod
    def lookup_release_group(cls, rg_id):
        if not rg_id:
            return []
            
        def do_lookup():
            return musicbrainzngs.get_release_group_by_id(rg_id, includes=["tags"])
        
        data = cls._retry(do_lookup)
        if not data:
            return []
            
        rg = data.get("release-group", {})
        tags = rg.get("tag-list", [])
        if tags:
            sorted_tags = sorted(tags, key=lambda x: int(x.get("count", 0)), reverse=True)
            return [t.get("name", "") for t in sorted_tags[:3]]
        return []

    @classmethod
    def lookup_artist(cls, artist_id):
        if not artist_id:
            return []
            
        def do_lookup():
            return musicbrainzngs.get_artist_by_id(artist_id, includes=["tags"])
        
        data = cls._retry(do_lookup)
        if not data:
            return []
            
        artist = data.get("artist", {})
        tags = artist.get("tag-list", [])
        if tags:
            sorted_tags = sorted(tags, key=lambda x: int(x.get("count", 0)), reverse=True)
            return [t.get("name", "") for t in sorted_tags[:3]]
        return []
