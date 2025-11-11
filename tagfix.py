#!/usr/bin/env python3
"""
Audio Metadata Editor
Supports FLAC, MP3, M4A, OGG, OPUS, WMA, and WAV formats.
"""

import os
import sys
from mutagen.flac import FLAC
from mutagen.mp3 import MP3
from mutagen.mp4 import MP4
from mutagen.oggvorbis import OggVorbis
from mutagen.oggopus import OggOpus
from mutagen.wave import WAVE
from mutagen.asf import ASF
from mutagen.id3 import ID3, TIT2, TPE1, TALB, TPE2, TCON, TDRC, TRCK, TPOS, COMM
from typing import List, Dict, Tuple, Optional
from collections import defaultdict

AVAILABLE_TAGS = {
    "1": "artist",
    "2": "albumartist",
    "3": "album",
    "4": "title",
    "5": "genre",
    "6": "date",
    "7": "tracknumber",
    "8": "discnumber",
    "9": "comment"
}

# Tags typically consistent across an album
GLOBAL_TAGS = {"artist", "albumartist", "album", "date", "genre"}

# Supported audio formats
SUPPORTED_EXTENSIONS = {'.flac', '.mp3', '.m4a', '.ogg', '.opus', '.wma', '.wav'}

# ID3 tag mapping for MP3/WAV files
ID3_TAG_MAP = {
    'title': TIT2,
    'artist': TPE1,
    'album': TALB,
    'albumartist': TPE2,
    'genre': TCON,
    'date': TDRC,
    'tracknumber': TRCK,
    'discnumber': TPOS,
    'comment': COMM
}

# MP4 tag mapping for M4A files
MP4_TAG_MAP = {
    'title': '\xa9nam',
    'artist': '\xa9ART',
    'album': '\xa9alb',
    'albumartist': 'aART',
    'genre': '\xa9gen',
    'date': '\xa9day',
    'tracknumber': 'trkn',
    'discnumber': 'disk',
    'comment': '\xa9cmt'
}


def find_audio_files(base_dir: str) -> List[str]:
    """
    Recursively locate all supported audio files within the specified directory.
    
    Args:
        base_dir: Root directory path to search
        
    Returns:
        List of absolute paths to audio files
    """
    base_dir = os.path.expanduser(base_dir.strip().strip('"').strip("'"))
    
    if not os.path.exists(base_dir):
        print(f"Error: Directory '{base_dir}' does not exist.")
        return []
    
    if not os.path.isdir(base_dir):
        print(f"Error: '{base_dir}' is not a directory.")
        return []
    
    audio_files = []
    for root, _, files in os.walk(base_dir):
        for file in files:
            if os.path.splitext(file.lower())[1] in SUPPORTED_EXTENSIONS:
                audio_files.append(os.path.join(root, file))
    
    return sorted(audio_files)


def load_audio_file(filepath: str):
    """
    Load audio file using appropriate mutagen class based on extension.
    
    Args:
        filepath: Path to audio file
        
    Returns:
        Mutagen audio object or None if unsupported
    """
    ext = os.path.splitext(filepath.lower())[1]
    
    try:
        if ext == '.flac':
            return FLAC(filepath)
        elif ext == '.mp3':
            return MP3(filepath)
        elif ext == '.m4a':
            return MP4(filepath)
        elif ext == '.ogg':
            return OggVorbis(filepath)
        elif ext == '.opus':
            return OggOpus(filepath)
        elif ext == '.wma':
            return ASF(filepath)
        elif ext == '.wav':
            return WAVE(filepath)
    except Exception as e:
        print(f"Error loading file: {e}")
        return None
    
    return None


def get_tag_value(audio, tag: str, filepath: str) -> Optional[str]:
    """
    Get tag value from audio file, handling different formats.
    
    Args:
        audio: Mutagen audio object
        tag: Tag name to retrieve
        filepath: Path to audio file (for format detection)
        
    Returns:
        Tag value as string or None
    """
    ext = os.path.splitext(filepath.lower())[1]
    
    try:
        if ext == '.mp3' or ext == '.wav':
            # ID3 tags
            if not hasattr(audio, 'tags') or audio.tags is None:
                return None
            tag_class = ID3_TAG_MAP.get(tag)
            if tag_class and tag_class.__name__ in audio.tags:
                if tag == 'comment':
                    return str(audio.tags[tag_class.__name__].text[0])
                return str(audio.tags[tag_class.__name__].text[0])
            return None
            
        elif ext == '.m4a':
            # MP4 tags
            mp4_tag = MP4_TAG_MAP.get(tag)
            if mp4_tag and mp4_tag in audio.tags:
                value = audio.tags[mp4_tag]
                if tag in ('tracknumber', 'discnumber'):
                    return str(value[0][0]) if value and value[0] else None
                return str(value[0]) if value else None
            return None
            
        else:
            # Vorbis comments (FLAC, OGG, OPUS, WMA)
            if tag in audio:
                return str(audio[tag][0]) if audio[tag] else None
            return None
            
    except Exception:
        return None


def set_tag_value(audio, tag: str, value: str, filepath: str) -> bool:
    """
    Set tag value for audio file, handling different formats.
    
    Args:
        audio: Mutagen audio object
        tag: Tag name to set
        value: Tag value
        filepath: Path to audio file (for format detection)
        
    Returns:
        True if successful, False otherwise
    """
    ext = os.path.splitext(filepath.lower())[1]
    
    try:
        if ext == '.mp3' or ext == '.wav':
            # ID3 tags
            if not hasattr(audio, 'tags') or audio.tags is None:
                audio.add_tags()
            
            tag_class = ID3_TAG_MAP.get(tag)
            if tag_class:
                if tag == 'comment':
                    audio.tags[tag_class.__name__] = tag_class(encoding=3, lang='eng', desc='', text=value)
                else:
                    audio.tags[tag_class.__name__] = tag_class(encoding=3, text=value)
            return True
            
        elif ext == '.m4a':
            # MP4 tags
            mp4_tag = MP4_TAG_MAP.get(tag)
            if mp4_tag:
                if tag == 'tracknumber':
                    audio.tags[mp4_tag] = [(int(value), 0)]
                elif tag == 'discnumber':
                    audio.tags[mp4_tag] = [(int(value), 0)]
                else:
                    audio.tags[mp4_tag] = [value]
            return True
            
        else:
            # Vorbis comments (FLAC, OGG, OPUS, WMA)
            audio[tag] = [value]
            return True
            
    except Exception as e:
        print(f"  Warning: Could not set {tag}: {e}")
        return False


def analyze_metadata(audio_files: List[str], selected_tags: List[str]) -> Dict[str, Dict]:
    """
    Analyze metadata across all files to show current values.
    
    Args:
        audio_files: List of audio file paths
        selected_tags: Tags to analyze
        
    Returns:
        Dictionary with metadata analysis
    """
    metadata_map = defaultdict(lambda: defaultdict(list))
    
    for filepath in audio_files:
        audio = load_audio_file(filepath)
        if audio is None:
            continue
        
        filename = os.path.basename(filepath)
        for tag in selected_tags:
            value = get_tag_value(audio, tag, filepath)
            metadata_map[tag][value if value else "[Not Set]"].append(filename)
    
    return metadata_map


def display_metadata_analysis(metadata_map: Dict[str, Dict], tag: str, audio_files: List[str]) -> None:
    """
    Display analysis of current metadata values for a specific tag.
    
    Args:
        metadata_map: Metadata analysis dictionary
        tag: Tag to display
        audio_files: List of all audio files
    """
    print(f"\nCurrent {tag.title()} Values:")
    print("-" * 60)
    
    tag_data = metadata_map.get(tag, {})
    
    if not tag_data:
        print("  No metadata found")
        return
    
    # Sort by value, with [Not Set] last
    sorted_values = sorted(tag_data.items(), 
                          key=lambda x: (x[0] == "[Not Set]", x[0]))
    
    for value, files in sorted_values:
        count = len(files)
        total = len(audio_files)
        percentage = (count / total * 100) if total > 0 else 0
        
        print(f"  '{value}' - {count} file(s) ({percentage:.1f}%)")
        
        # Show first few files as examples
        if count <= 3:
            for f in files:
                print(f"    - {f}")
        else:
            for f in files[:2]:
                print(f"    - {f}")
            print(f"    ... and {count - 2} more")


def setup_menu(audio_files: List[str]) -> Tuple[List[str], Dict[str, str]]:
    """
    Interactive setup menu for selecting metadata fields after showing current values.
    
    Args:
        audio_files: List of audio file paths
        
    Returns:
        Tuple containing (selected_tags, global_values)
    """
    print("\n" + "=" * 60)
    print("Setup Menu - Select Metadata Fields to Edit")
    print("=" * 60)
    
    for key, tag in sorted(AVAILABLE_TAGS.items()):
        print(f"  [{key}] {tag.title()}")
    
    print("\nInstructions: Enter numbers separated by spaces")
    print("Example: 1 3 4 7")
    
    while True:
        choices = input("\nYour selection: ").strip().split()
        selected_tags = [AVAILABLE_TAGS[c] for c in choices if c in AVAILABLE_TAGS]
        
        if selected_tags:
            break
        else:
            print("Error: No valid tags selected. Please try again.")
    
    print("\nSelected fields:", ", ".join(tag.title() for tag in selected_tags))
    
    # Analyze current metadata for selected tags
    print("\nAnalyzing current metadata...")
    metadata_map = analyze_metadata(audio_files, selected_tags)
    
    # Display current values and collect new values
    print("\n" + "=" * 60)
    print("Current Metadata Values")
    print("=" * 60)
    
    global_values = {}
    per_file_tags = []
    
    for tag in selected_tags:
        display_metadata_analysis(metadata_map, tag, audio_files)
        
        # Ask if this should be a global tag
        if tag in GLOBAL_TAGS:
            print(f"\nOptions for {tag.title()}:")
            print("  [g] Set global value (apply to all files)")
            print("  [i] Set individual values per file")
            print("  [s] Skip (no changes)")
            
            while True:
                choice = input("Choice: ").strip().lower()
                if choice in ('g', 'i', 's'):
                    break
                print("Error: Please enter 'g', 'i', or 's'.")
            
            if choice == 'g':
                new_value = input(f"New {tag.title()} value: ").strip()
                if new_value:
                    global_values[tag] = new_value
                else:
                    print(f"  Note: {tag.title()} will remain unchanged")
            elif choice == 'i':
                per_file_tags.append(tag)
        else:
            per_file_tags.append(tag)
    
    return selected_tags, global_values, per_file_tags


def edit_audio_files(audio_files: List[str], selected_tags: List[str], 
                    global_values: Dict[str, str], per_file_tags: List[str]) -> None:
    """
    Edit audio metadata for multiple files.
    
    Args:
        audio_files: List of audio file paths
        selected_tags: All selected metadata fields
        global_values: Global tag values to apply to all files
        per_file_tags: Tags that need per-file editing
    """
    if not audio_files:
        print("\nNotification: No supported audio files found.\n")
        return
    
    print(f"\n{'=' * 60}")
    print(f"Processing {len(audio_files)} Audio File(s)")
    print(f"{'=' * 60}")
    
    # Apply global values first if any
    if global_values:
        print("\nApplying global values...")
        for filepath in audio_files:
            try:
                audio = load_audio_file(filepath)
                if audio is None:
                    continue
                
                for tag, value in global_values.items():
                    set_tag_value(audio, tag, value, filepath)
                
                audio.save()
            except Exception as e:
                print(f"Error processing {os.path.basename(filepath)}: {e}")
        
        print(f"Global values applied to {len(audio_files)} file(s).")
    
    # Process per-file tags if any
    if not per_file_tags:
        print("\nNo per-file edits required. Operation complete.")
        return
    
    print(f"\n{'=' * 60}")
    print("Per-File Editing")
    print(f"{'=' * 60}")
    
    stats = {"processed": 0, "skipped": 0, "failed": 0}
    
    for idx, path in enumerate(audio_files, start=1):
        try:
            audio = load_audio_file(path)
            if audio is None:
                print(f"Error: Could not load {os.path.basename(path)}")
                stats["failed"] += 1
                continue
            
            filename = os.path.basename(path)
            file_ext = os.path.splitext(filename)[1].upper()
            
            print(f"\n[{idx}/{len(audio_files)}] File: {filename} {file_ext}")
            print("-" * 60)
            
            # Display current values for per-file tags
            print("Current values:")
            for tag in per_file_tags:
                current = get_tag_value(audio, tag, path)
                display_current = current if current else "[Not Set]"
                print(f"  {tag.title()}: {display_current}")
            
            # Offer option to skip
            print("\nOptions: [Enter] to edit | [s] to skip | [q] to quit")
            action = input("Action: ").strip().lower()
            
            if action == 'q':
                print("\nBatch operation terminated by user.")
                break
            elif action == 's':
                print(f"Skipped: {filename}")
                stats["skipped"] += 1
                continue
            
            # Prompt for per-file fields
            modified = False
            for tag in per_file_tags:
                current = get_tag_value(audio, tag, path)
                display_current = f"[{current}]" if current else "[Not Set]"
                new_val = input(f"  {tag.title()} {display_current}: ").strip()
                
                if new_val:
                    set_tag_value(audio, tag, new_val, path)
                    modified = True
            
            if modified:
                audio.save()
                print(f"Success: Metadata saved for {filename}")
                stats["processed"] += 1
            else:
                print(f"No changes made to {filename}")
                stats["skipped"] += 1
                
        except Exception as e:
            print(f"Error: Failed to process {path}")
            print(f"  Reason: {str(e)}")
            stats["failed"] += 1
    
    # Display summary
    print(f"\n{'=' * 60}")
    print("Batch Operation Summary")
    print(f"{'=' * 60}")
    if global_values:
        print(f"  Global edits: {len(audio_files)} file(s)")
    print(f"  Per-file processed: {stats['processed']}")
    print(f"  Per-file skipped:   {stats['skipped']}")
    print(f"  Failed:             {stats['failed']}")
    print()


def main_loop() -> None:
    """Main application loop with improved workflow."""
    print("=" * 60)
    print("Audio Metadata Editor - Professional Edition")
    print("=" * 60)
    print("Supports: FLAC, MP3, M4A, OGG, OPUS, WMA, WAV")
    print()
    
    while True:
        print("\n" + "=" * 60)
        print("Main Menu")
        print("=" * 60)
        print("  Enter directory path to begin")
        print("  [0] Exit application")
        
        directory = input("\nDirectory path: ").strip()
        
        if directory == "0":
            print("\nApplication terminated. Goodbye.")
            break
        elif not directory:
            print("Error: Please enter a valid path.")
            continue
        
        # Step 1: Find audio files
        audio_files = find_audio_files(directory)
        
        if not audio_files:
            print("\nNo supported audio files found in the specified directory.")
            continue
        
        print(f"\nFound {len(audio_files)} audio file(s).")
        
        # Step 2: Select tags and view current values
        selected_tags, global_values, per_file_tags = setup_menu(audio_files)
        
        # Confirm before processing
        print("\n" + "=" * 60)
        print("Summary")
        print("=" * 60)
        print(f"Files to process: {len(audio_files)}")
        print(f"Global changes: {len(global_values)}")
        print(f"Per-file tags: {len(per_file_tags)}")
        
        if global_values:
            print("\nGlobal values:")
            for tag, value in global_values.items():
                print(f"  {tag.title()}: {value}")
        
        while True:
            confirm = input("\nProceed with editing? (y/n): ").strip().lower()
            if confirm in ('y', 'n'):
                break
            print("Error: Please enter 'y' or 'n'.")
        
        if confirm == 'y':
            # Step 3: Edit files
            edit_audio_files(audio_files, selected_tags, global_values, per_file_tags)
        else:
            print("Operation cancelled.")


if __name__ == "__main__":
    try:
        main_loop()
    except KeyboardInterrupt:
        print("\n\nOperation interrupted by user. Exiting application.")
        sys.exit(0)
