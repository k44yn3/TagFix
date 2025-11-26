import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/audio_file.dart';

class DirectoryScanResult {
  final List<Directory> subdirectories;
  final List<AudioFile> audioFiles;
  
  const DirectoryScanResult(this.subdirectories, this.audioFiles);
}

class FileService {
  static const Set<String> supportedExtensions = {
    '.mp3',
    '.flac',
    '.m4a',
    '.ogg',
    '.opus',
    '.wma',
    '.wav'
  };

  Future<List<AudioFile>> scanDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      return [];
    }

    final List<AudioFile> audioFiles = [];

    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (supportedExtensions.contains(ext)) {
            audioFiles.add(AudioFile(
              path: entity.path,
              filename: p.basename(entity.path),
            ));
          }
        }
      }
    } catch (e) {
      print('Error scanning directory: $e');
    }

    audioFiles.sort((a, b) => a.filename.toLowerCase().compareTo(b.filename.toLowerCase()));

    return audioFiles;
  }

  Future<DirectoryScanResult> scanDirectoryNonRecursive(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      return DirectoryScanResult([], []);
    }

    final List<Directory> subdirectories = [];
    final List<AudioFile> audioFiles = [];

    try {
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        if (entity is Directory) {
          subdirectories.add(entity);
        } else if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (supportedExtensions.contains(ext)) {
            audioFiles.add(AudioFile(
              path: entity.path,
              filename: p.basename(entity.path),
            ));
          }
        }
      }
    } catch (e) {
      print('Error scanning directory: $e');
    }

    subdirectories.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
    audioFiles.sort((a, b) => a.filename.toLowerCase().compareTo(b.filename.toLowerCase()));

    return DirectoryScanResult(subdirectories, audioFiles);
  }

  Future<String?> renameFile(AudioFile file, String newFilename) async {
    try {
      final File f = File(file.path);
      if (!await f.exists()) return null;

      final String dir = p.dirname(file.path);
      String newPath = p.join(dir, newFilename);
      
      if (p.extension(newFilename).isEmpty) {
        newPath += p.extension(file.path);
      }

      if (await File(newPath).exists()) {
        throw Exception('File already exists');
      }

      await f.rename(newPath);
      return newPath;
    } catch (e) {
      print('Error renaming file: $e');
      return null;
    }
  }

  Future<bool> extractLyricsToFile(AudioFile file, String lyrics) async {
    try {
      final String dir = p.dirname(file.path);
      final String basename = p.basenameWithoutExtension(file.path);
      final String lyricsPath = p.join(dir, '$basename.lrc');
      
      final File f = File(lyricsPath);
      await f.writeAsString(lyrics);
      return true;
    } catch (e) {
      print('Error extracting lyrics: $e');
      return false;
    }
  }


  Future<bool> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      print('Error deleting file: $e');
      return false;
    }
  }

  Future<bool> deleteDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        return true;
      }
      return false;
    } catch (e) {
      print('Error deleting directory: $e');
      return false;
    }
  }
}
