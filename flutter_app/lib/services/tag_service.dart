import 'dart:typed_data';
import 'package:audiotags/audiotags.dart';
import '../models/audio_file.dart';

class TagService {
  Future<AudioFile> readTags(AudioFile file) async {
    try {
      final tag = await AudioTags.read(file.path);
      return file.copyWith(
        tags: tag,
        duration: tag?.duration,
      );
    } catch (e) {
      print('Error reading tags for ${file.path}: $e');
      return file.copyWith(hasError: true, errorMessage: e.toString());
    }
  }

  Future<bool> writeTags(AudioFile file, Tag tags) async {
    try {
      await AudioTags.write(file.path, tags);
      return true;
    } catch (e) {
      print('Error writing tags for ${file.path}: $e');
      return false;
    }
  }
  
  Future<bool> setCover(AudioFile file, List<int> imageData) async {
      try {
          final currentTag = file.tags ?? await AudioTags.read(file.path);
          
          final newTag = Tag(
              title: currentTag?.title,
              trackArtist: currentTag?.trackArtist,
              album: currentTag?.album,
              albumArtist: currentTag?.albumArtist,
              genre: currentTag?.genre,
              year: currentTag?.year,
              trackNumber: currentTag?.trackNumber,
              trackTotal: currentTag?.trackTotal,
              discNumber: currentTag?.discNumber,
              discTotal: currentTag?.discTotal,
              lyrics: currentTag?.lyrics,
              pictures: [
                  Picture(
                      pictureType: PictureType.coverFront,
                      mimeType: MimeType.jpeg,
                      bytes: Uint8List.fromList(imageData),
                  )
              ],
          );
          
          await AudioTags.write(file.path, newTag);
          return true;
      } catch (e) {
          print('Error setting cover for ${file.path}: $e');
          return false;
      }
  }
  
  Future<String?> getLyrics(AudioFile file) async {
    try {
      final tag = file.tags ?? await AudioTags.read(file.path);
      return tag?.lyrics;
    } catch (e) {
      print('Error reading lyrics for ${file.path}: $e');
      return null;
    }
  }
  
  Future<bool> setLyrics(AudioFile file, String lyrics) async {
    try {
      final currentTag = file.tags ?? await AudioTags.read(file.path);
      
      final newTag = Tag(
        title: currentTag?.title,
        trackArtist: currentTag?.trackArtist,
        album: currentTag?.album,
        albumArtist: currentTag?.albumArtist,
        genre: currentTag?.genre,
        year: currentTag?.year,
        trackNumber: currentTag?.trackNumber,
        trackTotal: currentTag?.trackTotal,
        discNumber: currentTag?.discNumber,
        discTotal: currentTag?.discTotal,
        lyrics: lyrics,
        pictures: currentTag?.pictures ?? [],
      );
      
      await AudioTags.write(file.path, newTag);
      return true;
    } catch (e) {
      print('Error setting lyrics for ${file.path}: $e');
      return false;
    }
  }
}
