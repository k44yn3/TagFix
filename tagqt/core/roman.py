import logging

logger = logging.getLogger(__name__)


class Romanizer:
    """Converts Korean/CJK text to romanized form using koroman."""

    @staticmethod
    def romanize_text(text):
        if not text:
            return ""
        try:
            from koroman import romanize
            return romanize(text)
        except ImportError:
            raise ImportError("koroman library is not installed. Install with: pip install koroman")
        except Exception as e:
            logger.error("Error romanizing text: %s", e)
            return text
