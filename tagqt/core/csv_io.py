"""CSV import/export utilities for audio file metadata."""

import csv
import os
import logging
logger = logging.getLogger(__name__)


def export_metadata_to_csv(files_data, filepath):
    if not files_data:
        return False, "No files to export"
    
    fieldnames = ['filepath', 'filename', 'title', 'artist', 'album', 'album_artist', 
                  'year', 'genre', 'disc_number', 'track_number', 'bpm', 'initial_key', 'comment', 'lyrics']
    
    try:
        with open(filepath, 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            
            for path, meta in files_data:
                row = {
                    'filepath': path,
                    'filename': os.path.basename(path),
                    'title': meta.title or '',
                    'artist': meta.artist or '',
                    'album': meta.album or '',
                    'album_artist': meta.album_artist or '',
                    'year': meta.year or '',
                    'genre': meta.genre or '',
                    'disc_number': meta.disc_number or '',
                    'track_number': meta.track_number or '',
                    'bpm': meta.bpm or '',
                    'initial_key': meta.initial_key or '',
                    'comment': meta.comment or '',
                    'lyrics': meta.lyrics or ''
                }
                writer.writerow(row)
        return True, None
    except Exception as e:
        return False, str(e)


def import_metadata_from_csv(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            return list(reader), None
    except Exception as e:
        return None, str(e)
