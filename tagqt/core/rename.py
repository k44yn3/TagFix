import re
import os
import logging
logger = logging.getLogger(__name__)

class Renamer:
    @staticmethod
    def sanitize_filename(filename):
        """Removes invalid characters from filename."""
        # Replace / \ : * ? " < > | with _
        return re.sub(r'[\\/*?:"<>|]', '_', filename)

    @staticmethod
    def tag_to_filename(pattern, metadata):
        """
        Generates a filename based on pattern and metadata.
        Pattern examples: %artist% - %title%, %track% %title%
        """
        if not metadata:
            return None
            
        # Map of pattern keys to metadata properties
        replacements = {
            '%artist%': metadata.artist or 'Unknown Artist',
            '%title%': metadata.title or 'Unknown Title',
            '%album%': metadata.album or 'Unknown Album',
            '%year%': metadata.year or '',
            '%track%': metadata.track_number or '',
            '%genre%': metadata.genre or '',
            '%albumartist%': metadata.album_artist or '',
            '%bpm%': metadata.bpm or '',
            '%key%': metadata.initial_key or ''
        }
        
        result = pattern
        for key, value in replacements.items():
            result = result.replace(key, str(value))
            
        return Renamer.sanitize_filename(result)

    @staticmethod
    def filename_to_tag(pattern, filename):
        """
        Parses filename using pattern to extract tags.
        Pattern examples: %artist% - %title%
        Returns a dictionary of extracted tags.
        """
        token_regex = re.compile(r'%(\w+)%')
        
        def replace_token(match):
            tag = match.group(1)
            return f"(?P<{tag}>.+)"
            
        parts = token_regex.split(pattern)

        final_regex = "^"
        tags_found = []
        
        for i, part in enumerate(parts):
            if i % 2 == 0:
                # Literal text
                final_regex += re.escape(part)
            else:
                # Token (tag)
                tag = part
                final_regex += f"(?P<{tag}>.+?)"
                tags_found.append(tag)
                
        final_regex += "$"
        
        try:
            match = re.match(final_regex, filename)
            if match:
                return match.groupdict()
        except Exception as e:
            logger.error(f"Error parsing filename: {e}")
            
        return None
