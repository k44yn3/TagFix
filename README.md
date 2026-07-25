<p align="center">
  <img src="assets/logo.png" alt="TagQt" width="420"/>
</p>

<p align="center">
  <strong>A music metadata editor built with Python and Qt</strong>
</p>

<p align="center">
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square&labelColor=1e1e2e&color=f38ba8" alt="License: MIT"/></a>
  <a href="https://github.com/near-link/tagqt"><img src="https://img.shields.io/badge/FOSS-100%25-success?style=flat-square&labelColor=1e1e2e&color=a6e3a1" alt="FOSS"/></a>
  <a href="https://github.com/near-link/tagqt"><img src="https://img.shields.io/badge/Platform-Windows%20%7C%20Linux-green?style=flat-square&labelColor=1e1e2e&color=cba6f7" alt="Platform"/></a>
  <a href="https://github.com/near-link/tagqt"><img src="https://img.shields.io/badge/Python-3.10%2B-blue?style=flat-square&labelColor=1e1e2e&color=89b4fa" alt="Python 3.10+"/></a>
</p>

## Screenshot

<p align="center">
  <img src="assets/screenshot.png" alt="TagQt Screenshot" width="800"/>
</p>

## What is this

TagQt is a desktop music metadata editor for Windows and Linux. It reads and writes tags for MP3, FLAC, OGG, M4A, and WAV files. You can edit files one at a time or select multiple files and apply changes in bulk.

The interface uses the Catppuccin color theme with four flavors: Latte, Frappé, Macchiato, and Mocha. There is a command palette (`Ctrl+K`) for quick access to every action.

## Features

TagQt can auto-tag files from MusicBrainz, filling in artist, album, year, track number, and genre. It fetches lyrics from multiple providers including Musixmatch (word-synced and line-synced) and LRCLIB. Provider order and selection are configurable. It can search and download album artwork with configurable cover resolution.

A built-in music player lets you play through your tracks in display order. When a track has LRC timestamps in its lyrics, the lyrics box highlights the current line in sync with playback.

Files can be batch renamed using tag patterns like `%artist% - %title%`. FLAC files can be re-encoded with hardware DAP block sizes and baseline JPEG artwork optimization. Korean and CJK text in lyrics and tags can be romanized automatically. Metadata can be imported and exported as CSV, and filename or tag case can be converted between title case, upper, and lower.

You can drag and drop files or folders directly onto the window to load them.

## Keyboard Shortcuts

| Shortcut | Action                                   |
| -------- | ---------------------------------------- |
| `Ctrl+O` | Open a folder                            |
| `Ctrl+S` | Save changes                             |
| `Ctrl+G` | Toggle global edit for all visible files |
| `Ctrl+A` | Select all files                         |
| `Ctrl+K` | Open the command palette                 |
| `Ctrl+Q` | Quit the app                             |
| `Escape` | Exit global edit mode                    |

## Installation

### From a Release

Download the latest build from [Releases](https://github.com/near-link/tagqt/releases). On Windows, run the installer `.exe`. On Linux, download the AppImage, make it executable with `chmod +x`, and run it.

### From Source

Requires Python 3.10 or later.

```bash
git clone https://github.com/near-link/tagqt.git
cd tagqt
pip install -r requirements.txt
python main.py
```

## Dependencies

| Package          | Purpose                                           |
| ---------------- | ------------------------------------------------- |
| `PySide6`        | Qt GUI framework                                  |
| `mutagen`        | Reads and writes audio metadata                   |
| `Pillow`         | Image processing for cover art                    |
| `requests`       | HTTP requests for lyrics, covers, and MusicBrainz |
| `musicbrainzngs` | MusicBrainz API client                            |
| `koroman`        | Korean and CJK romanization                       |
| `syncedlyrics`   | Musixmatch lyrics provider                        |

Optional: `ffmpeg` is needed for FLAC re-encoding and must be on your PATH.

## Building

Check [`.github/workflows/release.yml`](.github/workflows/release.yml) for the full build steps. The CI builds a Windows installer and a Linux AppImage on every version tag push.

## Contributing

Contributions are welcome. Open an issue or submit a pull request.
