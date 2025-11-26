import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/audio_file.dart';
import 'ffmpeg_manager.dart';

class FfmpegService {
  final FfmpegManager _ffmpegManager = FfmpegManager.instance;

  Future<bool> isAvailable() async {
    return await _ffmpegManager.isAvailable();
  }
  
  
  Future<String?> convertToWav(AudioFile file) async {
    return _convert(file, 'wav', ['-acodec', 'pcm_s16le']);
  }

  Future<String?> convertToFlac(AudioFile file) async {
    return _convert(file, 'flac', ['-acodec', 'flac']);
  }

  Future<String?> _convert(AudioFile file, String format, List<String> args) async {
    try {
      final String dir = path.dirname(file.path);
      final String filename = path.basenameWithoutExtension(file.path);
      final String outputDir = path.join(dir, '${path.basename(dir)} - $format');
      
      await Directory(outputDir).create(recursive: true);
      
      final String outputPath = path.join(outputDir, '$filename.$format');
      
      final List<String> processArgs = [
        '-i', file.path,
        ...args,
        '-y', // Overwrite
        outputPath
      ];

      final ffmpegPath = await _ffmpegManager.getFfmpegPath();
      final result = await Process.run(ffmpegPath, processArgs);
      
      if (result.exitCode != 0) {
        print('FFmpeg error: ${result.stderr}');
        return null;
      }
      
      await _copyMiscellaneousFiles(dir, outputDir);
      
      return outputDir;
    } catch (e) {
      print('Error converting file: $e');
      return null;
    }
  }
  
  Future<void> _copyMiscellaneousFiles(String sourceDir, String destDir) async {
    try {
      final sourceDirectory = Directory(sourceDir);
      final entities = sourceDirectory.listSync();
      
      const audioExtensions = {
        '.mp3', '.flac', '.m4a', '.wav', '.ogg', 
        '.opus', '.wma', '.aac', '.alac'
      };
      
      for (final entity in entities) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          
          if (audioExtensions.contains(ext)) {
            continue;
          }
          
          final fileName = path.basename(entity.path);
          final destPath = path.join(destDir, fileName);
          
          await entity.copy(destPath);
          print('Copied: $fileName');
        }
      }
    } catch (e) {
      print('Error copying miscellaneous files: $e');
    }
  }
}
