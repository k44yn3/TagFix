# tagfix - Audio Metadata Editor

A command-line tool for batch editing and organizing audio metadata.  
Supports **FLAC, MP3, M4A, OGG, OPUS, WMA, and WAV** formats using the **Mutagen** library.

---

## Requirements

- Python 3.8 or later  
- Mutagen library

If you prefer installing `mutagen` via your system's package manager instead of `pip`, use the appropriate command below:

- **Fedora**:
  ```bash
  sudo dnf install python-mutagen
  ```

- **Arch Linux / Manjaro**:
  ```bash
  sudo pacman -S python-mutagen
  ```

- **Debian / Ubuntu**:
  ```bash
  sudo apt install python3-mutagen
  ```

- **macOS (Homebrew)**:
  ```bash
  brew install mutagen
  ```

Alternatively, you can install it via `pip`:
```bash
pip install mutagen
```


---

## Usage

Run the script from a terminal:
```bash
python3 tagfix.py
```

### Steps
1. Enter the **directory path** containing your audio files.  
2. Select which metadata fields to edit from the setup menu.  
3. Review current tag values and choose:
   - **Global edits**: Apply a single value to all files.
   - **Per-file edits**: Manually enter values for each file.
4. Confirm to begin batch editing.

---

## Supported Tags

| Number | Tag          | Description |
|---------|---------------|-------------|
| 1 | artist | Artist name |
| 2 | albumartist | Album artist |
| 3 | album | Album title |
| 4 | title | Track title |
| 5 | genre | Music genre |
| 6 | date | Release year/date |
| 7 | tracknumber | Track number |
| 8 | discnumber | Disc number |
| 9 | comment | User comment |

---

## Notes

- The program automatically detects and loads supported audio formats.  
- Invalid or unreadable files are skipped with a warning.  
- You can cancel or skip files at any point during editing.  

---

## Exit

Type `0` in the main menu to exit the application.  
Press `Ctrl + C` anytime to stop safely.
