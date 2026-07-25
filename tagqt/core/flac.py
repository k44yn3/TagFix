import subprocess
import shutil
import os
import sys
import tempfile
from PySide6.QtWidgets import QApplication
from PySide6.QtCore import QMetaObject, Qt, Q_ARG
from tagqt.core.tags import MetadataHandler
from tagqt.core.dap import optimize_art_for_dap
import logging

logger = logging.getLogger(__name__)


def _get_all_encoders() -> list[tuple[str, str]]:
    """
    Returns an ordered list of all available encoders to try.
    Each item is a tuple of (binary_path, mode).

    Priority:
    1. System ffmpeg (full 48kHz/32-bit conversion, preferred)
    2. System flac (re-compression only)
    3. Bundled flac inside PyInstaller sys._MEIPASS (re-compression only, last resort)
    """
    encoders = []

    # 1. System ffmpeg — preferred, full 48kHz/32-bit conversion with DAP-safe 4096 block size
    system_ffmpeg = shutil.which("ffmpeg")
    if system_ffmpeg:
        encoders.append((system_ffmpeg, "ffmpeg"))

    # 2. System flac — re-compression only with 4096 block size
    system_flac = shutil.which("flac")
    if system_flac:
        encoders.append((system_flac, "flac"))

    # 3. Bundled flac (PyInstaller frozen binary) — last resort
    if getattr(sys, "frozen", False):
        name = "flac.exe" if sys.platform == "win32" else "flac"
        bundled = os.path.join(sys._MEIPASS, name)
        if os.path.isfile(bundled):
            if not system_flac or bundled != system_flac:
                encoders.append((bundled, "flac"))

    return encoders


def _build_cmd(binary, mode, filepath, temp_path):
    """Build the subprocess command for the given encoder mode."""
    if mode == "flac":
        # Xiph flac native CLI — re-compression with 4096 block size for DAP compatibility
        return [
            binary,
            "-b", "4096",
            "--best",
            "--force",
            "--silent",
            "-o", temp_path,
            filepath
        ]
    elif mode == "ffmpeg":
        # ffmpeg — full conversion to 24-bit 48kHz with 4096 frame/block size for DAP compatibility
        return [
            binary, '-y', '-i', filepath,
            '-map_metadata', '0',
            '-c:a', 'flac',
            '-frame_size', '4096',
            '-compression_level', '5',
            '-sample_fmt', 's32',
            '-ar', '48000',
            '-c:v', 'copy', temp_path
        ]
    return None


class FlacEncoder:
    """Handles FLAC re-encoding to 24-bit 48kHz and DAP hardware compatibility."""

    @staticmethod
    def is_flac_available():
        return shutil.which('flac') is not None

    @staticmethod
    def is_ffmpeg_available():
        return shutil.which('ffmpeg') is not None

    @staticmethod
    def get_available_encoder():
        if FlacEncoder.is_ffmpeg_available():
            return 'ffmpeg'
        elif FlacEncoder.is_flac_available():
            return 'flac'
        return None

    @staticmethod
    def reencode_flac(filepath, fix_dap_art=True):
        if not filepath.lower().endswith('.flac'):
            return False, "Not a FLAC file"

        # Capture metadata before encoding
        tags_to_preserve = {}
        cover_data = None
        try:
            original_meta = MetadataHandler(filepath)

            for attr in ['title', 'artist', 'album', 'year', 'genre',
                         'track_number', 'disc_number', 'album_artist', 'comment', 'lyrics',
                         'bpm', 'initial_key', 'isrc', 'publisher']:
                val = getattr(original_meta, attr)
                if val:
                    tags_to_preserve[attr] = val

            cover_data = original_meta.get_cover()
            if cover_data and fix_dap_art:
                # Optimize cover art to baseline JPEG <= 1000x1000 for DAP hardware compatibility
                opt_art = optimize_art_for_dap(cover_data)
                if opt_art:
                    cover_data = opt_art

        except Exception as e:
            logger.warning("Could not read original metadata: %s", e)

        temp_fd, temp_path = tempfile.mkstemp(suffix='.flac')
        os.close(temp_fd)
        if os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except Exception:
                pass

        encoders = _get_all_encoders()

        if not encoders:
            try:
                win = QApplication.activeWindow()
                if win and hasattr(win, 'show_toast'):
                    QMetaObject.invokeMethod(win, "show_toast", Qt.QueuedConnection,
                        Q_ARG(str, "FLAC encoder not found. Please install FLAC or ffmpeg "
                                   "and ensure it is in your system PATH to use re-encoding."))
            except Exception:
                pass
            return False, "FLAC encoder not found"

        last_error = None

        for binary, mode in encoders:
            if os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except Exception:
                    pass

            try:
                cmd = _build_cmd(binary, mode, filepath, temp_path)
                if cmd is None:
                    continue

                logger.info("Trying encoder: %s (mode=%s)", binary, mode)

                result = subprocess.run(
                    cmd,
                    capture_output=True,
                    check=True
                )

                # Encoding succeeded — restore metadata and optimized cover
                try:
                    new_meta = MetadataHandler(temp_path)

                    for key, value in tags_to_preserve.items():
                        setattr(new_meta, key, value)

                    if cover_data:
                        new_meta.set_cover(cover_data)

                    new_meta.save()

                except Exception as e:
                    logger.warning("Could not restore metadata: %s", e)

                shutil.move(temp_path, filepath)
                return True, None

            except subprocess.CalledProcessError as e:
                error_msg = e.stderr.decode() if e.stderr else str(e)
                logger.error("Encoder %s failed: %s", binary, error_msg)
                last_error = f"Encoding failed: {error_msg}"
                continue

            except Exception as e:
                logger.error("Encoder %s error: %s", binary, e)
                last_error = str(e)
                continue

        if os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except Exception:
                pass

        return False, last_error or "All available encoders failed"


class DependencyChecker:
    """Checks availability of optional external dependencies."""

    @staticmethod
    def check_koroman():
        try:
            import koroman
            return True, None
        except ImportError:
            return False, "koroman library is not installed. Install with: pip install koroman"

    @staticmethod
    def check_flac_tools():
        encoder = FlacEncoder.get_available_encoder()
        if encoder:
            return True, encoder
        return False, "Neither flac nor ffmpeg is installed. Please install one of them."