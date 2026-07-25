"""
DAP (Digital Audio Player) Compatibility Checker & Optimizer.
Specifically tuned for hardware players like the Snowsky Echo Mini DAP.

Key DAP limits enforced:
- FLAC/PCM Sample rate <= 192,000 Hz
- FLAC/PCM Bit depth <= 24-bit
- FLAC Max Block Size <= 4,608 samples per frame
- Album Art: Baseline (non-progressive) JPEG, <= 1000x1000 resolution, image/jpeg
- Filename: No emojis or unsupported complex Asian scripts (Hindi, Bengali, Khmer, Burmese)
"""

import os
import re
import io
import logging
from PIL import Image
from tagqt.core.tags import MetadataHandler

logger = logging.getLogger(__name__)

# Extensions supported by Snowsky Echo Mini hardware
SUPPORTED_EXTENSIONS = {'.flac', '.wav', '.ape', '.mp3', '.ogg', '.m4a', '.dsf', '.dff', '.wma'}
UNSUPPORTED_EXTENSIONS = {'.opus', '.aiff', '.wv', '.dts', '.dtshd', '.iso', '.sacd'}

EMOJI_PATTERN = re.compile(
    r'['
    r'\U0001f300-\U0001f64f'
    r'\U0001f680-\U0001f6ff'
    r'\U0001f900-\U0001f9ff'
    r'\U0001fa70-\U0001faff'
    r'\u2600-\u26ff'
    r'\u2700-\u27bf'
    r']'
)

COMPLEX_ASIAN_SCRIPTS_PATTERN = re.compile(
    r'['
    r'\u0900-\u097f'  # Devanagari (Hindi)
    r'\u0980-\u09ff'  # Bengali
    r'\u1780-\u17ff\u19e0-\u19ff'  # Khmer
    r'\u1000-\u109f\uaa60-\uaa7f\ua9e0-\ua9ff'  # Myanmar / Burmese
    r']'
)


def get_flac_max_block_size(filepath: str) -> int | None:
    """Read the max block size directly from a FLAC STREAMINFO header."""
    try:
        with open(filepath, 'rb') as f:
            if f.read(4) != b'fLaC':
                return None
            while True:
                header = f.read(4)
                if not header or len(header) < 4:
                    return None
                is_last = bool(header[0] & 0x80)
                block_type = header[0] & 0x7f
                block_len = int.from_bytes(header[1:4], 'big')
                if block_type == 0 and block_len >= 4:
                    payload = f.read(block_len)
                    return int.from_bytes(payload[2:4], 'big')
                f.seek(block_len, os.SEEK_CUR)
                if is_last:
                    return None
    except Exception as e:
        logger.debug("Failed to read FLAC block size for %s: %s", filepath, e)
        return None


def is_jpeg_progressive(data: bytes) -> bool:
    """Check if JPEG byte stream uses progressive scan structure (SOF2 marker 0xC2)."""
    if not data or not data.startswith(b'\xff\xd8'):
        return False
    idx = 2
    progressive_markers = {0xc2, 0xc6, 0xca, 0xce}
    baseline_markers = {0xc0, 0xc1, 0xc3, 0xc5, 0xc7, 0xc9, 0xcb, 0xcd, 0xcf}
    while idx + 4 < len(data):
        if data[idx] != 0xff:
            idx += 1
            continue
        marker = data[idx + 1]
        idx += 2
        while marker == 0xff and idx < len(data):
            marker = data[idx]
            idx += 1
        if marker in (0xd8, 0xd9):
            continue
        if idx + 2 > len(data):
            break
        length = int.from_bytes(data[idx:idx + 2], 'big')
        if length < 2:
            break
        if marker in progressive_markers:
            return True
        if marker in baseline_markers:
            return False
        idx += length
    return False


def check_filename_dap_compatibility(filename: str) -> tuple[bool, list[str]]:
    """Check filename for characters unsupported by DAP hardware."""
    issues = []
    if EMOJI_PATTERN.search(filename):
        issues.append("Filename contains emojis")
    if COMPLEX_ASIAN_SCRIPTS_PATTERN.search(filename):
        issues.append("Filename contains unsupported complex script (Hindi/Bengali/Khmer/Burmese)")
    return len(issues) == 0, issues


def optimize_art_for_dap(art_bytes: bytes, max_dim: int = 1000) -> bytes | None:
    """
    Convert image to a DAP-compatible baseline JPEG:
    - Format: JPEG
    - Encoding: Non-progressive (baseline)
    - Max resolution: 1000x1000 (scaled preserving aspect ratio)
    """
    if not art_bytes:
        return None
    try:
        img = Image.open(io.BytesIO(art_bytes))
        img = img.convert('RGB')
        if img.width > max_dim or img.height > max_dim:
            img.thumbnail((max_dim, max_dim), Image.Resampling.LANCZOS)

        output = io.BytesIO()
        img.save(output, format='JPEG', progressive=False, quality=92)
        return output.getvalue()
    except Exception as e:
        logger.error("Failed to optimize album art for DAP: %s", e)
        return None


def check_dap_compatibility(filepath: str) -> dict:
    """
    Evaluates audio file against Snowsky Echo Mini DAP compatibility requirements.

    Returns dict:
      - 'compatible': bool
      - 'status': 'SUPPORTED' | 'INCOMPATIBLE' | 'WARNING'
      - 'reasons': list of issue descriptions
      - 'details': dict of audio & art specs
    """
    filename = os.path.basename(filepath)
    ext = os.path.splitext(filepath)[1].lower()

    details = {
        'filename': filename,
        'extension': ext,
        'sample_rate': None,
        'bit_depth': None,
        'block_size': None,
        'art_present': False,
        'art_mime': None,
        'art_dimensions': None,
        'art_progressive': False,
    }

    reasons = []

    if ext in UNSUPPORTED_EXTENSIONS or ext not in SUPPORTED_EXTENSIONS:
        return {
            'compatible': False,
            'status': 'INCOMPATIBLE',
            'reasons': [f"Unsupported audio format '{ext}' (player will not display or play this format)"],
            'details': details,
        }

    # Audio metadata inspection
    try:
        meta = MetadataHandler(filepath)
        sr_hz = getattr(meta, 'sample_rate_hz', 0) or (meta.sample_rate * 1000)
        bd = meta.bit_depth
        details['sample_rate'] = sr_hz
        details['bit_depth'] = bd

        if sr_hz and sr_hz > 192000:
            reasons.append(f"Sample rate {sr_hz} Hz exceeds DAP limit of 192,000 Hz")

        if bd and bd > 24:
            reasons.append(f"Bit depth {bd}-bit exceeds DAP limit of 24-bit")

        if ext == '.flac':
            block_size = get_flac_max_block_size(filepath)
            details['block_size'] = block_size
            if block_size and block_size > 4608:
                reasons.append(f"FLAC block size {block_size} exceeds DAP hardware limit of 4,608 samples")

        # Album Art Inspection
        art_bytes = meta.get_cover()
        if art_bytes:
            details['art_present'] = True
            try:
                img = Image.open(io.BytesIO(art_bytes))
                fmt = (img.format or '').upper()
                details['art_mime'] = f"image/{fmt.lower()}"
                details['art_dimensions'] = (img.width, img.height)
                
                if fmt != 'JPEG':
                    reasons.append(f"Album art format is {fmt} (DAP requires baseline JPEG)")

                progressive = is_jpeg_progressive(art_bytes)
                details['art_progressive'] = progressive
                if progressive:
                    reasons.append("Album art is Progressive JPEG (DAP hardware requires Non-progressive/Baseline JPEG)")

                if img.width > 1000 or img.height > 1000:
                    reasons.append(f"Album art resolution {img.width}x{img.height} exceeds DAP limit of 1000x1000")

            except Exception as e:
                logger.warning("Could not analyze album art for %s: %s", filepath, e)
                reasons.append("Album art image data is invalid or corrupt")

    except Exception as e:
        logger.warning("Error inspecting DAP metadata for %s: %s", filepath, e)

    # Filename character checks
    fn_valid, fn_issues = check_filename_dap_compatibility(filename)
    if not fn_valid:
        reasons.extend(fn_issues)

    if not reasons:
        return {
            'compatible': True,
            'status': 'SUPPORTED',
            'reasons': ["File is fully compatible with DAP hardware"],
            'details': details,
        }
    else:
        return {
            'compatible': False,
            'status': 'INCOMPATIBLE',
            'reasons': reasons,
            'details': details,
        }
