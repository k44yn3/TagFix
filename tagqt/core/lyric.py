import requests
import logging
logger = logging.getLogger(__name__)

try:
    import syncedlyrics
    SYNCEDLYRICS_AVAILABLE = True
except ImportError:
    SYNCEDLYRICS_AVAILABLE = False


class LyricsFetcher:
    """Searches for synced and plain lyrics from lrclib.net."""
    BASE_URL = "https://lrclib.net/api/search"

    def search_lyrics(self, artist, title, album=None):
        params = {
            "q": f"{artist} {title}",
        }
        
        try:
            response = requests.get(self.BASE_URL, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            results = []
            for item in data:
                results.append({
                    "id": item.get("id"),
                    "trackName": item.get("trackName"),
                    "artistName": item.get("artistName"),
                    "albumName": item.get("albumName"),
                    "duration": item.get("duration"),
                    "syncedLyrics": item.get("syncedLyrics"),
                    "plainLyrics": item.get("plainLyrics"),
                    "isSynced": bool(item.get("syncedLyrics"))
                })
            return results
        except requests.exceptions.RequestException as e:
            logger.error(f"Error fetching lyrics: {e}")
            return []

    def search_with_providers(self, artist: str, title: str,
                               album: str | None,
                               providers: list[str]) -> list[dict]:
        """Query enabled providers and return a flat list of dialog-compatible results."""
        enabled = set(providers)
        priority = ["syncedlyrics_word", "syncedlyrics_line", "lrclib"]
        all_results: list[dict] = []

        for key in priority:
            if key not in enabled:
                continue
            try:
                if key in ("syncedlyrics_word", "syncedlyrics_line"):
                    import syncedlyrics
                    enhanced = key == "syncedlyrics_word"
                    lrc = syncedlyrics.search(f"{artist} {title}", enhanced=enhanced)
                    if lrc:
                        label = "Word Synced" if enhanced else "Line Synced"
                        all_results.append({
                            "trackName": title,
                            "artistName": artist,
                            "albumName": album or "",
                            "duration": 0,
                            "syncedLyrics": lrc,
                            "plainLyrics": None,
                            "isSynced": True,
                            "_provider": label,
                        })
                elif key == "lrclib":
                    all_results.extend(self.search_lyrics(artist, title, album))
            except Exception as e:
                logger.error(f"Lyrics provider {key!r} failed: {e}")
        return all_results

    def fetch_with_providers(self, artist: str, title: str,
                              providers: list[str]) -> tuple[str | None, str]:
        """
        Try each enabled provider in priority order and return the first result.

        Priority (regardless of the order stored in settings):
          1. syncedlyrics_word  — word-level sync, best experience
          2. syncedlyrics_line  — line-level sync via Musixmatch
          3. lrclib             — line-level or plain via LRCLIB

        Returns (lrc_text, provider_key) where lrc_text is None if nothing found.
        """
        enabled = set(providers)
        priority = ["syncedlyrics_word", "syncedlyrics_line", "lrclib"]

        for key in priority:
            if key not in enabled:
                continue
            try:
                if key == "syncedlyrics_word":
                    # calls syncedlyrics.search() directly rather than through
                    # a separate method so we only hit the API once per provider slot
                    import syncedlyrics
                    result = syncedlyrics.search(f"{artist} {title}", enhanced=True)
                    if result:
                        return result, key

                elif key == "syncedlyrics_line":
                    import syncedlyrics
                    result = syncedlyrics.search(f"{artist} {title}", enhanced=False)
                    if result:
                        return result, key

                elif key == "lrclib":
                    results = self.search_lyrics(artist, title)
                    if results:
                        best = results[0]
                        text = best.get("syncedLyrics") or best.get("plainLyrics")
                        if text:
                            return text, key

            except Exception as e:
                logger.error(f"Lyrics provider {key!r} failed: {e}")
                continue

        return None, ""
