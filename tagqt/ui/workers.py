from PySide6.QtCore import QObject, Signal, QThread
from tagqt.core.tags import MetadataHandler
from tagqt.core.musicbrainz import MusicBrainzClient
from tagqt.core.case import CaseConverter
from tagqt.core.flac import FlacEncoder
from tagqt.core.dap import check_dap_compatibility, optimize_art_for_dap
import os
import re
import time
import threading
import logging

logger = logging.getLogger(__name__)

try:
    import librosa
    LIBROSA_AVAILABLE = True
except ImportError:
    LIBROSA_AVAILABLE = False

class LyricsWorker(QObject):
    progress = Signal(int, int)
    result = Signal(str, str, str)
    finished = Signal()
    log = Signal(str)

    def __init__(self, files, lyrics_fetcher):
        super().__init__()
        self.files = files
        self.lyrics_fetcher = lyrics_fetcher
        self._stop_event = threading.Event()

    def stop(self):
        self._stop_event.set()

    def _is_synced(self, lyrics):
        if not lyrics:
            return False
        return lyrics.strip().startswith('[') and ']' in lyrics[:20]

    def _find_best_match(self, candidates, target_duration):
        if not candidates:
            return None, False
        
        synced_matches = []
        plain_matches = []
        
        for c in candidates:
            duration = c.get("duration") or 0
            diff = abs(duration - target_duration) if target_duration else 999
            
            if c.get("isSynced") and c.get("syncedLyrics"):
                synced_matches.append((c, diff))
            elif c.get("plainLyrics"):
                plain_matches.append((c, diff))
        
        if synced_matches:
            synced_matches.sort(key=lambda x: x[1])
            return synced_matches[0][0], True
        
        if plain_matches:
            plain_matches.sort(key=lambda x: x[1])
            return plain_matches[0][0], False
        
        return None, False

    def run(self):
        try:
            start_time = time.time()
            logger.debug(f"Starting batch lyrics fetch for {len(self.files)} files")
            
            for i, f in enumerate(self.files):
                if self._stop_event.is_set():
                    break

                self.progress.emit(i, len(self.files))
                self.result.emit(f, "Checking", "Checking for synced lyrics…")
                
                try:
                    md = MetadataHandler(f)
                    base_path = os.path.splitext(f)[0]
                    lrc_path = base_path + ".lrc"
                    
                    existing_lyrics = md.lyrics
                    existing_is_synced = self._is_synced(existing_lyrics)
                    
                    if existing_lyrics and existing_is_synced:
                        if not os.path.exists(lrc_path):
                            md.save_lyrics_file()
                            self.result.emit(f, "Skipped", "Already has synced lyrics, saved .lrc")
                        else:
                            self.result.emit(f, "Skipped", "Already has synced lyrics")
                        continue
                        
                    candidates = self.lyrics_fetcher.search_lyrics(md.artist, md.title, md.album)
                    best, is_synced = self._find_best_match(candidates, md.duration)
                    
                    if best and is_synced:
                        lyrics = best.get("syncedLyrics")
                        md.lyrics = lyrics
                        md.save()
                        
                        if existing_lyrics:
                            self.result.emit(f, "Updated", "Replaced with synced lyrics")
                        else:
                            self.result.emit(f, "Found", "Got synced lyrics")
                    elif best and not is_synced:
                        if existing_lyrics:
                            if not os.path.exists(lrc_path):
                                md.save_lyrics_file()
                                self.result.emit(f, "Skipped", "No synced version found, kept existing, saved .lrc")
                            else:
                                self.result.emit(f, "Skipped", "No synced version found, kept existing")
                        else:
                            md.lyrics = best.get("plainLyrics")
                            md.save()
                            self.result.emit(f, "Found", "Got plain lyrics (no synced version)")
                    else:
                        if existing_lyrics:
                            if not os.path.exists(lrc_path):
                                md.save_lyrics_file()
                                self.result.emit(f, "Skipped", "No results, kept existing, saved .lrc")
                            else:
                                self.result.emit(f, "Skipped", "No results, kept existing")
                        else:
                            self.result.emit(f, "Missing", "No results found")
                except Exception as e:
                    logger.debug(f"Error fetching lyrics for {f}: {e}")
                    self.result.emit(f, "Error", str(e))
                    
            logger.debug(f"Batch lyrics finished in {time.time() - start_time:.2f}s")
            self.progress.emit(len(self.files), len(self.files))
        finally:
            self.finished.emit()

class AutoTagWorker(QObject):
    progress = Signal(int, int)
    result = Signal(str, str, str)
    finished = Signal()
    log = Signal(str)

    def __init__(self, files, skip_existing=True):
        super().__init__()
        self.files = files
        self.skip_existing = skip_existing
        self._stop_event = threading.Event()

    def stop(self):
        self._stop_event.set()

    @staticmethod
    def is_generic(val):
        if not val:
            return True
        generic_terms = ["unknown", "generic", "various", "track", "audio"]
        if isinstance(val, str) and val.lower().strip() in generic_terms:
            return True
        if isinstance(val, list) and any(v.lower().strip() in generic_terms for v in val):
            return True
        return False

    @staticmethod
    def is_empty(val):
        if val is None:
            return True
        if isinstance(val, str):
            return not val.strip()
        if isinstance(val, list):
            return not val
        return False

    @staticmethod
    def extract_title_from_filename(filepath):
        basename = os.path.splitext(os.path.basename(filepath))[0]
        cleaned = re.sub(r'^[\d]+[\s.\-_]+', '', basename)
        cleaned = re.sub(r'^\d{1,2}\s*[-_.\s]\s*', '', cleaned)
        cleaned = cleaned.strip(' -_.')
        return cleaned if cleaned else basename

    def run(self):
        try:
            groups = {}
            skipped_early = 0
            
            for f in self.files:
                if self._stop_event.is_set():
                    break
                try:
                    md = MetadataHandler(f)
                    artist = md.artist or md.album_artist
                    album = md.album

                    if self.skip_existing:
                        needs_tagging = (
                            self.is_generic(md.genre) or 
                            self.is_empty(md.disc_number) or 
                            self.is_empty(md.track_number) or
                            self.is_empty(md.year)
                        )
                    else:
                        needs_tagging = True
                    
                    if artist and album and needs_tagging:
                        key = (artist, album)
                        if key not in groups:
                            groups[key] = []
                        groups[key].append(f)
                    elif not artist or not album:
                        self.result.emit(f, "Skipped", "Needs artist and album tags")
                        skipped_early += 1
                    elif not needs_tagging:
                        self.result.emit(f, "Skipped", "All tags already present")
                        skipped_early += 1
                except Exception as e:
                    self.result.emit(f, "Error", str(e))
                    skipped_early += 1

            processed_count = skipped_early
            total_files = len(self.files)
            self.progress.emit(processed_count, total_files)
            
            for (artist, album), group_files in groups.items():
                if self._stop_event.is_set():
                    break
                
                self.log.emit(f"Looking up: {artist} - {album}")
                release = MusicBrainzClient.search_release(artist, album)
                
                if not release:
                    for f in group_files:
                        self.result.emit(f, "Not Found", f"'{album}' by '{artist}' not on MusicBrainz")
                        processed_count += 1
                        self.progress.emit(processed_count, total_files)
                    continue
                    
                release_id = release.get("id")
                release_title = release.get("title", album)
                album_year = release.get("year")
                album_genres = release.get("genres", [])
                
                release_details = MusicBrainzClient.lookup_release(release_id, None) if release_id else None
                disc_count = release_details.get("disc_count", 1) if release_details else 1
                
                for f in group_files:
                    if self._stop_event.is_set():
                        break
                    processed_count += 1
                    self.progress.emit(processed_count, total_files)
                    
                    try:
                        md = MetadataHandler(f)
                        changes = []
                        
                        def should_update(current_val):
                            if not self.skip_existing:
                                return True
                            return self.is_empty(current_val)
                        
                        title_to_match = md.title
                        match_source = "title"
                        
                        if self.is_empty(title_to_match):
                            title_to_match = self.extract_title_from_filename(f)
                            match_source = "filename"
                        
                        track_details = MusicBrainzClient.lookup_release(release_id, title_to_match)
                        track_matched = track_details and track_details.get("track_position")
                        
                        if not track_matched and match_source == "title":
                            fallback_title = self.extract_title_from_filename(f)
                            if fallback_title != title_to_match:
                                track_details = MusicBrainzClient.lookup_release(release_id, fallback_title)
                                if track_details and track_details.get("track_position"):
                                    track_matched = True
                        
                        if album_year and should_update(md.year):
                            md.year = album_year
                            changes.append("year")
                            
                        if release.get("artist") and should_update(md.album_artist):
                            md.album_artist = release["artist"]
                            changes.append("album_artist")
                        
                        genres_to_use = []
                        if track_details and track_details.get("genres"):
                            genres_to_use = track_details["genres"]
                        elif release_details and release_details.get("genres"):
                            genres_to_use = release_details["genres"]
                        elif album_genres:
                            genres_to_use = album_genres
                            
                        if genres_to_use and should_update(md.genre):
                            md.genre = [g.title() for g in genres_to_use]
                            changes.append("genre")

                        if track_matched:
                            if track_details.get("track_disc") and should_update(md.disc_number):
                                disc = str(track_details["track_disc"])
                                if disc_count > 1:
                                    disc = f"{disc}/{disc_count}"
                                md.disc_number = disc
                                changes.append("disc")
                            
                            if track_details.get("track_position") and should_update(md.track_number):
                                md.track_number = str(track_details["track_position"])
                                changes.append("track")
                                
                            if track_details.get("track_count") and should_update(md.track_total):
                                md.track_total = str(track_details["track_count"])
                                changes.append("track_total")
                        
                        if changes:
                            md.save()
                            self.result.emit(f, "Updated", f"Added: {', '.join(changes)}")
                        elif not track_matched:
                            self.result.emit(f, "Not Matched", "Couldn't match this track in the release")
                        else:
                            self.result.emit(f, "Skipped", "All tags already present")
                            
                    except Exception as e:
                        self.result.emit(f, "Error", str(e))
            
            self.progress.emit(total_files, total_files)
        finally:
            self.finished.emit()

class FolderLoaderWorker(QObject):
    progress = Signal(int, int)
    finished = Signal(list, str)
    log = Signal(str)

    def __init__(self, folder_path):
        super().__init__()
        self.folder_path = folder_path
        self._stop_event = threading.Event()

    def stop(self):
        self._stop_event.set()

    def run(self):
        finished_emitted = False
        try:
            paths = []
            for root, dirs, filenames in os.walk(self.folder_path):
                if self._stop_event.is_set():
                    break
                for filename in filenames:
                    if filename.lower().endswith(('.mp3', '.flac', '.ogg', '.m4a', '.wav')):
                        paths.append(os.path.join(root, filename))
            
            if self._stop_event.is_set():
                return

            results = []
            total = len(paths)
            for i, path in enumerate(paths):
                if self._stop_event.is_set():
                    break
                try:
                    md = MetadataHandler(path)
                    results.append((path, md))
                except Exception as e:
                    self.log.emit(f"Error reading {path}: {e}")
                
                if i % 10 == 0: # Update progress every 10 files to avoid signal overhead
                    self.progress.emit(i, total)
            
            if self._stop_event.is_set():
                return

            self.finished.emit(results, self.folder_path)
            finished_emitted = True
        finally:
            if not finished_emitted:
                self.finished.emit([], self.folder_path)

class RenameWorker(QObject):
    progress = Signal(int, int)
    result = Signal(str, str, str)
    finished = Signal()
    log = Signal(str)

    def __init__(self, rename_data):
        """
        rename_data: dict of {old_path: new_name}
        """
        super().__init__()
        self.rename_data = rename_data
        self._stop_event = threading.Event()

    def stop(self):
        self._stop_event.set()

    def run(self):
        try:
            total = len(self.rename_data)
            for i, (old_path, new_name) in enumerate(self.rename_data.items()):
                if self._stop_event.is_set():
                    break
                
                self.progress.emit(i, total)
                
                try:
                    dir_path = os.path.dirname(old_path)
                    new_path = os.path.join(dir_path, new_name)
                    
                    if old_path != new_path:
                        if os.path.exists(new_path):
                            self.result.emit(old_path, "Error", f"File already exists: {new_name}")
                        else:
                            os.rename(old_path, new_path)
                            self.result.emit(old_path, "Success", f"Renamed to {new_name}")
                    else:
                        self.result.emit(old_path, "Skipped", "Name unchanged")
                except Exception as e:
                    self.result.emit(old_path, "Error", str(e))
                    
            self.progress.emit(total, total)
        finally:
            self.finished.emit()

class CoverFetchWorker(QObject):
    progress = Signal(int, int)
    result = Signal(str, str, str)
    finished = Signal()
    log = Signal(str)

    def __init__(self, files, cover_manager):
        super().__init__()
        self.files = files
        self.cover_manager = cover_manager
        self._stop_event = threading.Event()

    def stop(self):
        self._stop_event.set()

    def run(self):
        try:
            total = len(self.files)
            processed_folders = set()
            
            for i, f in enumerate(self.files):
                if self._stop_event.is_set(): break
                self.progress.emit(i, total)
                
                try:
                    md = MetadataHandler(f)
                        
                    candidates = self.cover_manager.search_cover_candidates(md.artist, md.album)
                    if candidates:
                        url = candidates[0]["url"]
                        data = self.cover_manager.download_and_process_cover(url)
                        if data:
                            md.set_cover(data, max_size=500)
                            md.save()
                            
                            folder = os.path.dirname(f)
                            if folder not in processed_folders:
                                md.save_cover_file(data, overwrite=True)
                                processed_folders.add(folder)
                                
                            self.result.emit(f, "Found", "Cover downloaded")
                        else:
                            self.result.emit(f, "Missing", "Download failed")
                    else:
                        self.result.emit(f, "Missing", "No candidates found")
                except Exception as e:
                    self.result.emit(f, "Error", str(e))
                    
            self.progress.emit(total, total)
        finally:
            self.finished.emit()

class CoverResizeWorker(QObject):
    progress = Signal(int, int)
    result = Signal(str, str, str)
    finished = Signal()
    log = Signal(str)

    def __init__(self, files):
        super().__init__()
        self.files = files
        self._stop_event = threading.Event()

    def stop(self):
        self._stop_event.set()

    def run(self):
        try:
            total = len(self.files)
            for i, f in enumerate(self.files):
                if self._stop_event.is_set(): break
                self.progress.emit(i, total)
                
                try:
                    md = MetadataHandler(f)
                    cover = md.get_cover()
                    if cover:
                        md.set_cover(cover, max_size=500)
                        md.save()
                        self.result.emit(f, "Success", "Cover resized")
                    else:
                        self.result.emit(f, "Skipped", "No cover found")
                except Exception as e:
                    self.result.emit(f, "Error", str(e))
                    
            self.progress.emit(total, total)
        finally:
            self.finished.emit()

class RomanizeWorker(QObject):
    progress = Signal(int, int)
    result = Signal(str, str, str)
    finished = Signal()
    log = Signal(str)

    def __init__(self, files, romanizer):
        super().__init__()
        self.files = files
        self.romanizer = romanizer
        self._stop_event = threading.Event()

    def stop(self):
        self._stop_event.set()

    def run(self):
        try:
            total = len(self.files)
            for i, f in enumerate(self.files):
                if self._stop_event.is_set(): break
                self.progress.emit(i, total)
                
                try:
                    md = MetadataHandler(f)
                    val = md.lyrics
                    if val:
                        new_val = self.romanizer.romanize_text(val)
                        if new_val != val:
                            md.lyrics = new_val
                            md.save()
                            self.result.emit(f, "Success", "Lyrics romanized")
                        else:
                            self.result.emit(f, "Skipped", "No change needed")
                    else:
                        self.result.emit(f, "Skipped", "No lyrics found")
                except Exception as e:
                    self.result.emit(f, "Error", str(e))
                    
            self.progress.emit(total, total)
        finally:
            self.finished.emit()

class CaseConvertWorker(QObject):
    progress = Signal(int, int)
    result = Signal(str, str, str)
    finished = Signal()
    log = Signal(str)

    def __init__(self, files, mode):
        super().__init__()
        self.files = files
        self.mode = mode
        self._stop_event = threading.Event()

    def stop(self):
        self._stop_event.set()

    def run(self):
        try:
            total = len(self.files)
            fields = ['title', 'artist', 'album', 'genre', 'album_artist', 'comment', 'publisher']
            
            for i, f in enumerate(self.files):
                if self._stop_event.is_set(): break
                self.progress.emit(i, total)
                
                try:
                    md = MetadataHandler(f)
                    changed = False
                    for field in fields:
                        val = getattr(md, field)
                        if val:
                            new_val = val
                            if self.mode == "title": new_val = CaseConverter.to_title_case(val)
                            elif self.mode == "sentence": new_val = CaseConverter.to_sentence_case(val)
                            elif self.mode == "upper": new_val = CaseConverter.to_upper_case(val)
                            elif self.mode == "lower": new_val = CaseConverter.to_lower_case(val)
                            
                            if new_val != val:
                                setattr(md, field, new_val)
                                changed = True
                    if changed:
                        md.save()
                        self.result.emit(f, "Success", "Case converted")
                    else:
                        self.result.emit(f, "Skipped", "No change")
                except Exception as e:
                    self.result.emit(f, "Error", str(e))
                    
            self.progress.emit(total, total)
        finally:
            self.finished.emit()

class FlacReencodeWorker(QObject):
    progress = Signal(int, int)
    result = Signal(str, str, str)
    finished = Signal()
    log = Signal(str)

    def __init__(self, files):
        super().__init__()
        self.files = files
        self._stop_event = threading.Event()

    def stop(self):
        self._stop_event.set()

    def run(self):
        try:
            total = len(self.files)
            for i, f in enumerate(self.files):
                if self._stop_event.is_set():
                    break
                self.progress.emit(i, total)
                ext = os.path.splitext(f)[1].lower()
                try:
                    if ext == '.flac':
                        success, error = FlacEncoder.reencode_flac(f, fix_dap_art=True)
                        if success:
                            self.result.emit(f, "Success", "Re-encoded to 24-bit 48kHz (4096 block size & baseline JPEG art)")
                        else:
                            self.result.emit(f, "Error", error or "Re-encode failed")
                    else:
                        meta = MetadataHandler(f)
                        cover_data = meta.get_cover()
                        if cover_data:
                            opt_art = optimize_art_for_dap(cover_data)
                            if opt_art:
                                meta.set_cover(opt_art)
                                meta.save()
                                self.result.emit(f, "Success", "Fixed album art (baseline JPEG <= 1000x1000)")
                            else:
                                self.result.emit(f, "Skipped", "Album art already optimized")
                        else:
                            self.result.emit(f, "Skipped", "No embedded album art to optimize")
                except Exception as e:
                    self.result.emit(f, "Error", str(e))
            self.progress.emit(total, total)
        finally:
            self.finished.emit()

class CsvImportWorker(QObject):
    progress = Signal(int, int)
    result = Signal(str, str, str)
    finished = Signal()
    log = Signal(str)

    def __init__(self, rows):
        super().__init__()
        self.rows = rows
        self._stop_event = threading.Event()

    def stop(self):
        self._stop_event.set()

    def run(self):
        try:
            total = len(self.rows)
            for i, row in enumerate(self.rows):
                if self._stop_event.is_set(): break
                self.progress.emit(i, total)
                
                fpath = row.get('filepath')
                if not fpath or not os.path.exists(fpath):
                    self.result.emit(fpath or "Unknown", "Error", "File not found")
                    continue
                try:
                    md = MetadataHandler(fpath)
                    changed = False
                    fields = ['title', 'artist', 'album', 'album_artist', 'year', 'genre', 'track_number', 'bpm', 'initial_key', 'comment', 'lyrics']
                    for field in fields:
                        if row.get(field):
                            setattr(md, field, row[field])
                            changed = True
                    if changed:
                        md.save()
                        self.result.emit(fpath, "Success", "Metadata imported")
                    else:
                        self.result.emit(fpath, "Skipped", "No changes in CSV")
                except Exception as e:
                    self.result.emit(fpath, "Error", str(e))
                    
            self.progress.emit(total, total)
        finally:
            self.finished.emit()

class DuplicateScanWorker(QObject):
    """Scans loaded files for duplicate title+artist pairs."""
    finished = Signal(list)  # list of (key, [paths])

    def __init__(self, files):
        super().__init__()
        self.files = files  # list of (path, title, artist)

    def run(self):
        from collections import defaultdict
        groups = defaultdict(list)
        for path, title, artist in self.files:
            key = (title.strip().lower(), artist.strip().lower())
            if key[0] or key[1]:  # skip rows with both blank
                groups[key].append(path)
        dupes = [(key, paths) for key, paths in groups.items() if len(paths) > 1]
        self.finished.emit(dupes)


class SaveWorker(QObject):
    progress = Signal(int, int)
    result = Signal(str, str, str)
    finished = Signal()
    log = Signal(str)

    def __init__(self, files, changes):
        super().__init__()
        self.files = files
        self.changes = changes
        self._stop_event = threading.Event()

    def stop(self):
        self._stop_event.set()

    def run(self):
        try:
            total = len(self.files)
            for i, f in enumerate(self.files):
                if self._stop_event.is_set(): break
                self.progress.emit(i, total)
                
                try:
                    md = MetadataHandler(f)
                    for key, value in self.changes.items():
                        setattr(md, key, value)
                    md.save()
                    self.result.emit(f, "Success", "Metadata updated")
                except Exception as e:
                    self.result.emit(f, "Error", str(e))
                    
            self.progress.emit(total, total)
        finally:
            self.finished.emit()


class BpmDetectWorker(QThread):
    finished = Signal(int)
    failed = Signal(str)

    def __init__(self, filepath):
        super().__init__()
        self._filepath = filepath

    def run(self):
        try:
            import librosa
            y, sr = librosa.load(self._filepath, sr=None, mono=True)
            tempo, _ = librosa.beat.beat_track(y=y, sr=sr)
            bpm = round(float(tempo))
            self.finished.emit(bpm)
        except Exception as e:
            self.failed.emit(str(e))


class UndoBatchWorker(QObject):
    progress = Signal(int, int)
    result = Signal(str, str, str)
    finished = Signal()

    def __init__(self, snapshot):
        super().__init__()
        self.snapshot = snapshot
        self._stop_event = threading.Event()

    def stop(self):
        self._stop_event.set()

    def run(self):
        items = list(self.snapshot.snapshots.items())
        total = len(items)
        try:
            for i, (filepath, tags) in enumerate(items):
                if self._stop_event.is_set():
                    break
                try:
                    md = MetadataHandler(filepath)
                    for field, value in tags.items():
                        setattr(md, field, value)
                    md.save()
                    self.result.emit(filepath, "Success", "Tags restored")
                except Exception as e:
                    self.result.emit(filepath, "Error", str(e))
                self.progress.emit(i + 1, total)
        finally:
            self.finished.emit()


class DapCheckWorker(QObject):
    progress = Signal(int, int)
    result = Signal(str, str, str)
    finished = Signal()

    def __init__(self, filepaths):
        super().__init__()
        self.filepaths = filepaths
        self._stop_event = threading.Event()

    def stop(self):
        self._stop_event.set()

    def run(self):
        total = len(self.filepaths)
        try:
            for idx, fp in enumerate(self.filepaths, start=1):
                if self._stop_event.is_set():
                    break
                self.progress.emit(idx, total)
                try:
                    info = check_dap_compatibility(fp)
                    status = info['status']
                    reasons = "; ".join(info['reasons'])
                    self.result.emit(fp, status, reasons)
                except Exception as e:
                    self.result.emit(fp, "Error", f"Check failed: {e}")
            self.progress.emit(total, total)
        finally:
            self.finished.emit()

