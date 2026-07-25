import time

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from PIL import Image
from io import BytesIO
import logging
logger = logging.getLogger(__name__)

class CoverArtManager:
    """Manages cover art searching and downloading from iTunes and MusicBrainz."""

    ITUNES_API_URL = "https://itunes.apple.com/search"

    def __init__(self):
        self.session = requests.Session()
        retries = Retry(total=3, backoff_factor=1, status_forcelist=[500, 502, 503, 504])
        self.session.mount('https://', HTTPAdapter(max_retries=retries))
        self.session.mount('http://', HTTPAdapter(max_retries=retries))

    def _retry(self, func, max_retries=3):
        """Execute func with exponential backoff retry on network errors."""
        for attempt in range(max_retries):
            try:
                return func()
            except (requests.exceptions.RequestException, OSError) as e:
                if attempt < max_retries - 1:
                    time.sleep(2 ** attempt)
                    continue
                logger.error(f"Network error after {max_retries} retries: {e}")
                return None
        return None

    def download_and_process_cover(self, url):
        def do_download():
            response = self.session.get(url, timeout=15)
            response.raise_for_status()
            return response.content

        content = self._retry(do_download)
        if not content:
            return None

        try:
            img = Image.open(BytesIO(content))
            img = img.convert("RGB")
            img = img.resize((500, 500), Image.Resampling.LANCZOS)
            
            output = BytesIO()
            img.save(output, format="JPEG", quality=90)
            return output.getvalue()
        except Exception as e:
            logger.error(f"Error processing cover: {e}")
            return None

    def search_cover_musicbrainz(self, artist, album):
        def do_search():
            query = f'artist:"{artist}" AND release:"{album}"'
            url = "https://musicbrainz.org/ws/2/release-group"
            params = {
                "query": query,
                "fmt": "json"
            }
            headers = {"User-Agent": "tagqt/1.0 ( contact@example.com )"}
            
            response = self.session.get(url, params=params, headers=headers, timeout=10)
            response.raise_for_status()
            return response.json()

        data = self._retry(do_search)
        if data and data.get("release-groups"):
            rg_id = data["release-groups"][0]["id"]
            cover_url = f"https://coverartarchive.org/release-group/{rg_id}/front"
            return cover_url
        return None

    def search_cover(self, artist, album):
        url = self.search_cover_musicbrainz(artist, album)
        if url:
            return url
            
        return self.search_cover_itunes(artist, album)

    def search_cover_candidates(self, artist, album):
        """Returns a list of cover candidates."""
        candidates = []
        # iTunes
        try:
            params = {
                "term": f"{artist} {album}",
                "media": "music",
                "entity": "album",
                "limit": 5
            }
            response = self.session.get(self.ITUNES_API_URL, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            for item in data.get("results", []):
                url = item.get("artworkUrl100")
                if url:
                    url = url.replace("100x100bb", "1000x1000bb")
                    candidates.append({
                        "album": item.get("collectionName"),
                        "artist": item.get("artistName"),
                        "url": url,
                        "source": "iTunes",
                        "size": "1000x1000"
                    })
        except Exception as e:
            logger.error(f"Error searching iTunes candidates: {e}")
            
        # MusicBrainz (Simplified for candidates, usually just one front image per release group)
        try:
            mb_url = self.search_cover_musicbrainz(artist, album)
            if mb_url:
                candidates.append({
                    "album": album,
                    "artist": artist,
                    "url": mb_url,
                    "source": "MusicBrainz",
                    "size": "Unknown"
                })
        except Exception:
            pass
            
        return candidates

    def search_cover_itunes(self, artist, album):
        cands = self.search_cover_candidates(artist, album)
        if cands:
            return cands[0]["url"]
        return None
