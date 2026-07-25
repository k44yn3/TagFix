import mutagen
from mutagen import File
from mutagen.easyid3 import EasyID3
from mutagen.id3 import ID3, ID3NoHeaderError, USLT, APIC, COMM, TKEY
from mutagen.flac import FLAC, Picture
from mutagen.oggvorbis import OggVorbis
from mutagen.mp4 import MP4, MP4Cover
import os
import base64
from PIL import Image
import io
import logging
logger = logging.getLogger(__name__)

def _get_comment(id3, _):
    frames = id3.getall('COMM')
    return [f.text[0] for f in frames if f.text]

def _set_comment(id3, _, value):
    id3.delall('COMM')
    id3.add(COMM(
        encoding=3,
        lang='eng',
        desc='',
        text=value
    ))

def _delete_comment(id3, _):
    id3.delall('COMM')

try:
    EasyID3.RegisterKey('comment', _get_comment, _set_comment, _delete_comment)
except Exception:
    pass

try:
    EasyID3.RegisterTextKey('initialkey', 'TKEY')
except Exception:
    pass

class MetadataHandler:
    """Reads and writes audio file metadata tags across MP3, FLAC, OGG, M4A formats."""

    def __init__(self, filepath):
        self.filepath = filepath
        self.audio = None
        self._lyrics_changed = False
        self.load_file()

    def load_file(self):
        try:
            self.audio = mutagen.File(self.filepath, easy=True)
            if self.audio is None:
                try:
                    self.audio = EasyID3(self.filepath)
                except ID3NoHeaderError:
                    self.audio = mutagen.File(self.filepath)
                    self.audio.add_tags()
        except Exception as e:
            logger.error(f"Error loading file {self.filepath}: {e}")

    def get_tag(self, tag):
        if self.audio and tag in self.audio:
            return self.audio[tag][0]
        return ""

    def set_tag(self, tag, value):
        if self.audio:
            try:
                if isinstance(value, list):
                    deduped = list(dict.fromkeys(str(v) for v in value))
                    self.audio[tag] = deduped
                else:
                    self.audio[tag] = [str(value)]
            except Exception as e:
                logger.warning(f"Warning: could not set tag '{tag}': {e}")

    def save(self):
        try:
            if self.audio:
                self.audio.save()
                if self._lyrics_changed and self.lyrics:
                    self.save_lyrics_file()
                    self._lyrics_changed = False
        except Exception as e:
            logger.warning(f"Warning: save failed: {e}")

    def save_lyrics_file(self):
        """Saves lyrics to a .lrc file with the same name as the audio file."""
        if not self.lyrics:
            return
            
        try:
            base_path = os.path.splitext(self.filepath)[0]
            lrc_path = base_path + ".lrc"
            
            with open(lrc_path, 'w', encoding='utf-8') as f:
                f.write(self.lyrics)
        except Exception as e:
            logger.error(f"Error saving lyrics file: {e}")

    def save_cover_file(self, data=None, overwrite=True):
        """
        Saves cover art to cover.jpg in the same directory.
        If data is provided, uses it. Otherwise tries to get from tags.
        If overwrite is False, checks if file exists first.
        """
        try:
            if data is None:
                data = self.get_cover()
            
            if not data:
                return

            dir_path = os.path.dirname(self.filepath)
            cover_path = os.path.join(dir_path, "cover.jpg")
            
            if not overwrite and os.path.exists(cover_path):
                return
                
            with open(cover_path, 'wb') as f:
                f.write(data)
        except Exception as e:
            logger.error(f"Error saving cover file: {e}")

    @property
    def title(self):
        try:
            val = self.get_tag('title')
            return val if val else ''
        except Exception:
            return ''

    @title.setter
    def title(self, value):
        self.set_tag('title', value)

    @property
    def artist(self):
        try:
            val = self.get_tag('artist')
            return val if val else ''
        except Exception:
            return ''

    @artist.setter
    def artist(self, value):
        self.set_tag('artist', value)

    @property
    def album(self):
        try:
            val = self.get_tag('album')
            return val if val else ''
        except Exception:
            return ''

    @album.setter
    def album(self, value):
        self.set_tag('album', value)

    @property
    def year(self):
        try:
            val = self.get_tag('date')
            return val if val else ''
        except Exception:
            return ''

    @year.setter
    def year(self, value):
        self.set_tag('date', value)

    @property
    def genre(self):
        try:
            val = self.get_tag('genre')
            return val if val else ''
        except Exception:
            return ''

    @genre.setter
    def genre(self, value):
        self.set_tag('genre', value)

    @property
    def track_number(self):
        try:
            val = self.get_tag('tracknumber')
            return val if val else ''
        except Exception:
            return ''

    @track_number.setter
    def track_number(self, value):
        self.set_tag('tracknumber', value)

    @property
    def disc_number(self):
        try:
            val = self.get_tag('discnumber')
            if self.audio and isinstance(self.audio, (FLAC, OggVorbis)):
                if '/' not in str(val) and 'DISCTOTAL' in self.audio:
                    total = self.audio['DISCTOTAL'][0]
                    return f"{val}/{total}"
            return val if val else ''
        except Exception:
            return ''

    @disc_number.setter
    def disc_number(self, value):
        if self.audio and isinstance(self.audio, (FLAC, OggVorbis)) and value and '/' in str(value):
            try:
                num, total = str(value).split('/')
                self.set_tag('discnumber', num)
                self.audio['DISCTOTAL'] = [str(total)]
                return
            except ValueError:
                pass
        self.set_tag('discnumber', value)

    @property
    def track_total(self):
        if self.audio and isinstance(self.audio, (FLAC, OggVorbis)):
            if 'TRACKTOTAL' in self.audio:
                return self.audio['TRACKTOTAL'][0]
        return ""

    @track_total.setter
    def track_total(self, value):
        if self.audio and isinstance(self.audio, (FLAC, OggVorbis)):
            if value:
                self.audio['TRACKTOTAL'] = [str(value)]
            elif 'TRACKTOTAL' in self.audio:
                del self.audio['TRACKTOTAL']

    @property
    def album_artist(self):
        try:
            val = self.get_tag('albumartist')
            return val if val else ''
        except Exception:
            return ''

    @album_artist.setter
    def album_artist(self, value):
        self.set_tag('albumartist', value)

    @property
    def comment(self):
        try:
            val = self.get_tag('comment')
            return val if val else ''
        except Exception:
            return ''

    @comment.setter
    def comment(self, value):
        if isinstance(self.audio, EasyID3):
            if value:
                self.audio['comment'] = [str(value)]
            else:
                if 'comment' in self.audio:
                    del self.audio['comment']
        else:
            self.set_tag('comment', value)

    @property
    def lyrics(self):
        """Returns lyrics from tags."""
        if self.audio is None:
            return ""
            
        try:
            if isinstance(self.audio, (ID3, EasyID3)) or (hasattr(self.audio, 'tags') and isinstance(self.audio.tags, (ID3, EasyID3))):
                tags = self.audio if isinstance(self.audio, ID3) else self.audio.tags
                if tags:
                    for key in tags.keys():
                        if key.startswith('USLT:'):
                            return tags[key].text
            
            elif isinstance(self.audio, (FLAC, OggVorbis)):
                if 'LYRICS' in self.audio:
                    return self.audio['LYRICS'][0]
            
            elif isinstance(self.audio, MP4):
                if '\xa9lyr' in self.audio:
                    return self.audio['\xa9lyr'][0]
                    
        except Exception as e:
            logger.error(f"Error getting lyrics: {e}")
        return ""

    @lyrics.setter
    def lyrics(self, value):
        """Sets lyrics to tags."""
        if self.audio is None:
            return

        self._lyrics_changed = True

        try:
            # ID3 (MP3)
            if isinstance(self.audio, (ID3, EasyID3)) or (hasattr(self.audio, 'tags') and isinstance(self.audio.tags, (ID3, EasyID3))):
                tags = self.audio if isinstance(self.audio, ID3) else self.audio.tags
                if tags is not None:
                    to_del = [k for k in tags.keys() if k.startswith('USLT:')]
                    for k in to_del:
                        del tags[k]
                    
                    if value:
                        tags.add(USLT(
                            encoding=3,
                            lang='eng', # Default to eng
                            desc='',
                            text=value
                        ))
            
            # FLAC
            elif isinstance(self.audio, (FLAC, OggVorbis)):
                if value:
                    self.audio['LYRICS'] = value
                elif 'LYRICS' in self.audio:
                    del self.audio['LYRICS']
            
            # MP4
            elif isinstance(self.audio, MP4):
                if value:
                    self.audio['\xa9lyr'] = value
                elif '\xa9lyr' in self.audio:
                    del self.audio['\xa9lyr']
                
        except Exception as e:
            logger.error(f"Error setting lyrics: {e}")

    @property
    def bpm(self):
        try:
            val = self.get_tag('bpm')
            return val if val else ''
        except Exception:
            return ''

    @bpm.setter
    def bpm(self, value):
        self.set_tag('bpm', value)

    @property
    def initial_key(self):
        try:
            val = self.get_tag('initialkey')
            return val if val else ''
        except Exception:
            return ''

    @initial_key.setter
    def initial_key(self, value):
        self.set_tag('initialkey', value)

    @property
    def isrc(self):
        try:
            val = self.get_tag('isrc')
            return val if val else ''
        except Exception:
            return ''

    @isrc.setter
    def isrc(self, value):
        self.set_tag('isrc', value)

    @property
    def publisher(self):
        try:
            val = self.get_tag('organization')
            return val if val else ''
        except Exception:
            return ''

    @publisher.setter
    def publisher(self, value):
        self.set_tag('organization', value)

    @property
    def duration(self):
        try:
            if self.audio and hasattr(self.audio, 'info') and self.audio.info:
                return int(self.audio.info.length)
        except Exception:
            pass
        return 0

    @property
    def bitrate(self):
        try:
            if self.audio and hasattr(self.audio, 'info') and hasattr(self.audio.info, 'bitrate'):
                return int(self.audio.info.bitrate / 1000) # kbps
        except Exception:
            pass
        return 0

    @property
    def sample_rate(self):
        try:
            if self.audio and hasattr(self.audio, 'info') and hasattr(self.audio.info, 'sample_rate'):
                return int(self.audio.info.sample_rate / 1000) # kHz
        except Exception:
            pass
        return 0

    @property
    def filesize(self):
        try:
            size_bytes = os.path.getsize(self.filepath)
            return round(size_bytes / (1024 * 1024), 2) # MB
        except Exception:
            pass
        return 0.0

    def get_cover(self):
        try:
            if isinstance(self.audio, EasyID3):
                id3_obj = ID3(self.audio.filename)
                frames = id3_obj.getall('APIC')
                return frames[0].data if frames else None

            elif isinstance(self.audio, FLAC):
                pics = self.audio.pictures
                return pics[0].data if pics else None

            elif isinstance(self.audio, OggVorbis):
                blocks = self.audio.get('metadata_block_picture', [])
                if blocks:
                    pic = Picture(base64.b64decode(blocks[0]))
                    return pic.data
                return None

            elif isinstance(self.audio, MP4):
                covers = self.audio.get('covr', [])
                return bytes(covers[0]) if covers else None

        except Exception as e:
            logger.warning(f"Warning: could not read cover art: {e}")
            return None

    def set_cover(self, data, max_size=None):
        if max_size:
            img = Image.open(io.BytesIO(data))
            img.thumbnail((max_size, max_size))
            buf = io.BytesIO()
            img.save(buf, format='JPEG')
            data = buf.getvalue()

        try:
            if isinstance(self.audio, EasyID3):
                id3_obj = ID3(self.audio.filename)
                id3_obj.delall('APIC')
                id3_obj.add(APIC(
                    encoding=3,
                    mime='image/jpeg',
                    type=3,
                    desc='Cover',
                    data=data
                ))
                id3_obj.save(self.audio.filename)

            elif isinstance(self.audio, FLAC):
                pic = Picture()
                pic.type = 3
                pic.mime = 'image/jpeg'
                pic.desc = 'Cover'
                pic.data = data
                self.audio.clear_pictures()
                self.audio.add_picture(pic)

            elif isinstance(self.audio, OggVorbis):
                pic = Picture()
                pic.type = 3
                pic.mime = 'image/jpeg'
                pic.desc = 'Cover'
                pic.data = data
                self.audio['metadata_block_picture'] = [
                    base64.b64encode(pic.write()).decode('ascii')
                ]

            elif isinstance(self.audio, MP4):
                self.audio['covr'] = [
                    MP4Cover(data, imageformat=MP4Cover.FORMAT_JPEG)
                ]

        except Exception as e:
            logger.warning(f"Warning: could not save cover art: {e}")
