import 'dart:typed_data';
import 'dart:io';
import 'package:audiotags/audiotags.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/audio_file.dart';
import '../models/directory_item.dart';
import '../services/file_service.dart';
import '../services/tag_service.dart';
import '../services/ffmpeg_service.dart';
import '../services/romanization_service.dart';
import '../services/lyrics_service.dart';
import '../services/cover_service.dart';

class AppState extends ChangeNotifier {
  final FileService _fileService = FileService();
  final TagService _tagService = TagService();
  final FfmpegService _ffmpegService = FfmpegService();
  final RomanizationService _romanizationService = RomanizationService();

  List<AudioFile> _files = [];
  List<AudioFile> get files => _files;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _rootDirectory;  // Initial selected folder
  String? _currentDirectory;  // Current navigation path
  String? get currentDirectory => _currentDirectory;
  
  List<Directory> _subdirectories = [];  // Subdirectories in current folder
  List<Directory> get subdirectories => _subdirectories;
  
  List<String> _breadcrumbSegments = [];  // Path segments for breadcrumb
  List<String> get breadcrumbSegments => _breadcrumbSegments;

  AudioFile? _selectedFile;
  AudioFile? get selectedFile => _selectedFile;
  
  bool _isBatchMode = false;
  bool get isBatchMode => _isBatchMode;
  
  AudioFile? _batchTemplate;
  AudioFile? get batchTemplate => _batchTemplate;

  final Map<String, String> _batchPendingLyrics = {};
  
  final Set<String> _batchDirtyFields = {};
  
  int _batchTotalFiles = 0;
  int get batchTotalFiles => _batchTotalFiles;

  List<AudioFile> _batchFiles = [];
  List<AudioFile> get batchFiles => _batchFiles;

  Future<void> toggleBatchMode(bool enabled) async {
    if (enabled) {
      _isLoading = true;
      notifyListeners();
      
      if (_currentDirectory != null) {
        _batchFiles = await getAllFilesRecursive();
        _batchTotalFiles = _batchFiles.length;
        
        for (int i = 0; i < _batchFiles.length; i++) {
          if (_batchFiles[i].tags == null) {
            try {
              _batchFiles[i] = await _tagService.readTags(_batchFiles[i]);
            } catch (e) {
              print('Error reading tags for ${_batchFiles[i].path}: $e');
            }
          }
        }
      } else {
        _batchFiles = [];
        _batchTotalFiles = 0;
      }
      
      Tag? initialTags;
      if (_batchFiles.isNotEmpty) {
        initialTags = _batchFiles.first.tags;
      }
      
      _batchTemplate = AudioFile(
        path: '', 
        filename: '',
        tags: Tag(
          title: null, // Unique per file
          trackArtist: initialTags?.trackArtist,
          album: initialTags?.album,
          year: initialTags?.year,
          genre: initialTags?.genre,
          trackNumber: null, // Unique per file
          discNumber: null, // Unique per file
          pictures: initialTags?.pictures ?? [],
        ),
      );
      _batchPendingLyrics.clear();
      
      _isBatchMode = true; // Set flag AFTER template is ready
      _isLoading = false;
    } else {
      _isBatchMode = false;
      _batchTemplate = null;
      _batchPendingLyrics.clear();
      _batchFiles = []; // Clear batch files
      _batchTotalFiles = 0;
    }
    notifyListeners();
  }
  

  Future<void> saveBatchChanges() async {
    if (_batchTemplate == null || _currentDirectory == null) return;
    
    _isLoading = true;
    notifyListeners();
    
    final allFiles = _batchFiles;
    
    for (final file in _batchFiles) {
      if (file.pendingLyrics != null) {
        _batchPendingLyrics[file.path] = file.pendingLyrics!;
      }
    }
    
    final templateTags = _batchTemplate!.tags;
    int successCount = 0;
    
    for (int i = 0; i < allFiles.length; i++) {
      var file = allFiles[i];
      
      if (_batchPendingLyrics.containsKey(file.path)) {
        file = file.copyWith(pendingLyrics: _batchPendingLyrics[file.path]);
      }
      
      Tag? currentTags = file.tags;
      if (currentTags == null) {
        try {
          currentTags = await _tagService.readTags(file).then((f) => f.tags);
        } catch (e) {
          print('Error reading tags for ${file.path}: $e');
        }
      }
      
      final newTags = Tag(
        title: currentTags?.title, // Unique, keep original
        trackArtist: (_batchDirtyFields.contains('artist') && templateTags?.trackArtist != null) 
            ? templateTags!.trackArtist 
            : currentTags?.trackArtist,
        album: (_batchDirtyFields.contains('album') && templateTags?.album != null)
            ? templateTags!.album
            : currentTags?.album,
        albumArtist: (_batchDirtyFields.contains('albumArtist') && templateTags?.albumArtist != null)
            ? templateTags!.albumArtist
            : currentTags?.albumArtist,
        genre: (_batchDirtyFields.contains('genre') && templateTags?.genre != null)
            ? templateTags!.genre
            : currentTags?.genre,
        year: (_batchDirtyFields.contains('year')) ? templateTags?.year : currentTags?.year,
        trackNumber: currentTags?.trackNumber, // Unique
        trackTotal: currentTags?.trackTotal,
        discNumber: currentTags?.discNumber, // Unique
        discTotal: currentTags?.discTotal,
        lyrics: currentTags?.lyrics, // Lyrics handled separately via pendingLyrics
        pictures: currentTags?.pictures ?? [],
      );
      
      if (newTags != currentTags) {
        await _tagService.writeTags(file, newTags);
      }
      
      if (file.pendingCover == null && _batchTemplate!.pendingCover != null) {
        file = file.copyWith(pendingCover: _batchTemplate!.pendingCover);
      }
      
      file = file.copyWith(
        extractLyrics: _batchTemplate!.extractLyrics,
        romanizeLyrics: _batchTemplate!.romanizeLyrics,
      );
      
      await savePendingChanges(file);
      
      try {
        _batchFiles[i] = await _tagService.readTags(file);
      } catch (e) {
        print('Error reloading tags for ${file.path}: $e');
      }
      
      successCount++;
    }
    
    
    _isLoading = false;
    _batchPendingLyrics.clear();
    
    for (int i = 0; i < _batchFiles.length; i++) {
        _batchFiles[i] = _batchFiles[i].copyWith(
            batchStatus: 'Saved',
            isProcessing: false,
            clearPendingLyrics: true,
            clearPendingCover: true
        );
    }
    
    notifyListeners();
  }

  Future<void> batchFetchLyrics() async {
    if (_batchTemplate == null || _currentDirectory == null) return;
    
    _isLoading = true; // Locks the UI
    _isFetchingLyrics = true;
    notifyListeners();
    
    final lyricsService = LyricsService();
    int successCount = 0;
    
    for (int i = 0; i < _batchFiles.length; i++) {
      var file = _batchFiles[i];
      
      _batchFiles[i] = file.copyWith(isProcessing: true, batchStatus: 'Finding lyrics...');
      notifyListeners(); // Animate progress
      
      if (file.tags == null || file.duration == null) {
        try {
          file = await _tagService.readTags(file);
        } catch (e) {
          print('Error reading tags for ${file.path}: $e');
        }
      }
      
    
    final artist = (file.tags?.trackArtist != null && file.tags!.trackArtist!.isNotEmpty)
        ? file.tags!.trackArtist!
        : (file.tags?.albumArtist != null && file.tags!.albumArtist!.isNotEmpty)
            ? file.tags!.albumArtist!
            : (_batchTemplate!.tags?.trackArtist ?? '');
            
    final album = (file.tags?.album != null && file.tags!.album!.isNotEmpty)
        ? file.tags!.album
        : (_batchTemplate!.tags?.album);
        
    final title = file.tags?.title ?? p.basenameWithoutExtension(file.filename);
    
    if (artist.isEmpty || title.isEmpty) {
      _batchFiles[i] = _batchFiles[i].copyWith(isProcessing: false, batchStatus: 'Skipped (No Metadata)');
      notifyListeners();
      continue;
    }
    
    try {
      final bestMatch = await lyricsService.getBestMatch(
        artist: artist,
        title: title,
        album: album,
        duration: file.duration,
      );
      
      if (bestMatch != null) {
        String? lyrics = bestMatch.syncedLyrics ?? bestMatch.plainLyrics;
        
        if (lyrics != null) {
          if (_batchTemplate!.romanizeLyrics) {
             _batchFiles[i] = _batchFiles[i].copyWith(batchStatus: 'Romanizing...');
             notifyListeners();
             
            final romanized = await _romanizationService.romanize(lyrics);
            if (romanized != null) {
              lyrics = romanized;
            }
          }
          
          _batchFiles[i] = _batchFiles[i].copyWith(
              pendingLyrics: lyrics,
              isProcessing: false,
              batchStatus: 'Done'
          );
          
          _batchPendingLyrics[file.path] = lyrics;
          
          successCount++;
          } else {
             _batchFiles[i] = _batchFiles[i].copyWith(isProcessing: false, batchStatus: 'Not Found');
          }
        } else {
             _batchFiles[i] = _batchFiles[i].copyWith(isProcessing: false, batchStatus: 'Not Found');
        }
      } catch (e) {
        print('Error fetching lyrics for ${file.filename}: $e');
        _batchFiles[i] = _batchFiles[i].copyWith(isProcessing: false, batchStatus: 'Error');
      }
      notifyListeners();
    }
    
    _isLoading = false; // Unlocks the UI
    _isFetchingLyrics = false;
    notifyListeners();
    
    print('Batch fetch completed. Updated $successCount files.');
  }

  Future<void> batchFetchCovers({bool replaceExisting = false}) async {
    if (_batchTemplate == null || _currentDirectory == null) return;
    
    _isLoading = true;
    notifyListeners();
    
    final coverService = CoverService();
    int successCount = 0;
    
    for (int i = 0; i < _batchFiles.length; i++) {
      var file = _batchFiles[i];
      
      if (!replaceExisting && (file.tags?.pictures.isNotEmpty == true || file.pendingCover != null)) {
        continue;
      }
      
      _batchFiles[i] = file.copyWith(isProcessing: true, batchStatus: 'Finding cover...');
      notifyListeners();
      
      if (file.tags == null) {
        try {
          file = await _tagService.readTags(file);
        } catch (e) {
          print('Error reading tags for ${file.path}: $e');
        }
      }
      
      final artist = file.tags?.trackArtist ?? file.tags?.albumArtist ?? '';
      final album = file.tags?.album ?? '';
      
      if (artist.isEmpty || album.isEmpty) {
        _batchFiles[i] = _batchFiles[i].copyWith(isProcessing: false, batchStatus: 'Skipped (No Metadata)');
        notifyListeners();
        continue;
      }
      
      try {
        final coverBytes = await coverService.fetchCover(artist, album);
        
        if (coverBytes != null) {
          _batchFiles[i] = _batchFiles[i].copyWith(
            pendingCover: coverBytes,
            isProcessing: false,
            batchStatus: 'Done'
          );
          
          successCount++;
        } else {
          _batchFiles[i] = _batchFiles[i].copyWith(isProcessing: false, batchStatus: 'Not Found');
        }
      } catch (e) {
        print('Error fetching cover for ${file.filename}: $e');
        _batchFiles[i] = _batchFiles[i].copyWith(isProcessing: false, batchStatus: 'Error');
      }
      notifyListeners();
    }
    
    _isLoading = false;
    notifyListeners();
    print('Batch cover fetch completed. Updated $successCount files.');
  }

  Future<void> batchConvertToFlac() async {
    if (_batchFiles.isEmpty) return;
    
    _isLoading = true;
    notifyListeners();
    
    int successCount = 0;
    
    for (int i = 0; i < _batchFiles.length; i++) {
      var file = _batchFiles[i];
      
      _batchFiles[i] = file.copyWith(isProcessing: true, batchStatus: 'Converting to FLAC...');
      notifyListeners();
      
      final result = await _ffmpegService.convertToFlac(file);
      
      if (result != null) {
        _batchFiles[i] = _batchFiles[i].copyWith(isProcessing: false, batchStatus: 'Converted');
        successCount++;
      } else {
        _batchFiles[i] = _batchFiles[i].copyWith(isProcessing: false, batchStatus: 'Conversion Failed');
      }
      notifyListeners();
    }
    
    _isLoading = false;
    notifyListeners();
  }  
  String? _searchQuery;
  String? get searchQuery => _searchQuery;
  
  List<AudioFile> get filteredFiles {
    if (_searchQuery == null || _searchQuery!.isEmpty) {
      return _files;
    }
    
    final query = _searchQuery!.toLowerCase();
    return _files.where((file) {
      final title = file.tags?.title?.toLowerCase() ?? '';
      final artist = file.tags?.trackArtist?.toLowerCase() ?? '';
      final album = file.tags?.album?.toLowerCase() ?? '';
      
      return title.contains(query) || 
             artist.contains(query) || 
             album.contains(query);
    }).toList();
  }

  Future<void> scanDirectory(String path) async {
    _isLoading = true;
    _rootDirectory = path;
    _currentDirectory = path;
    _updateBreadcrumbs();
    notifyListeners();

    final result = await _fileService.scanDirectoryNonRecursive(path);
    _subdirectories = result.subdirectories;
    _files = result.audioFiles;
    
    _isLoading = false;
    notifyListeners();
    
    _loadTags();
  }

  Future<void> navigateToDirectory(String path) async {
    _isLoading = true;
    _currentDirectory = path;
    _updateBreadcrumbs();
    notifyListeners();

    final result = await _fileService.scanDirectoryNonRecursive(path);
    _subdirectories = result.subdirectories;
    _files = result.audioFiles;
    
    _isLoading = false;
    notifyListeners();
    
    _loadTags();
  }

  Future<void> navigateUp() async {
    if (_currentDirectory == null || _currentDirectory == _rootDirectory) return;
    
    final parentDir = Directory(_currentDirectory!).parent.path;
    await navigateToDirectory(parentDir);
  }

  Future<void> navigateToBreadcrumb(int index) async {
    if (index < 0 || index >= _breadcrumbSegments.length) return;
    
    String path = _rootDirectory!;
    for (int i = 1; i <= index; i++) {
      path = p.join(path, _breadcrumbSegments[i]);
    }
    
    await navigateToDirectory(path);
  }

  void _updateBreadcrumbs() {
    if (_rootDirectory == null || _currentDirectory == null) {
      _breadcrumbSegments = [];
      return;
    }

    if (_currentDirectory == _rootDirectory) {
      _breadcrumbSegments = [p.basename(_rootDirectory!)];
      return;
    }

    final relativePath = p.relative(_currentDirectory!, from: _rootDirectory!);
    final segments = p.split(relativePath);
    
    _breadcrumbSegments = [p.basename(_rootDirectory!), ...segments];
  }

  Future<void> _loadTags() async {
    for (int i = 0; i < _files.length; i++) {
      if (_files[i].tags == null) {
        _files[i] = await _tagService.readTags(_files[i]);
        notifyListeners(); // Notify on every update might be too much, maybe throttle?
      }
    }
  }

  Future<List<AudioFile>> getAllFilesRecursive() async {
    if (_currentDirectory == null) return [];
    return await _fileService.scanDirectory(_currentDirectory!);
  }

  void selectFile(AudioFile file) {
    _selectedFile = file;
    notifyListeners();
  }
  
  void setSearchQuery(String? query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> updateTags(AudioFile file, {
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? year,
    String? genre,
    String? trackNumber,
    String? discNumber,
  }) async {
    if (file.tags == null) return;

    final newTags = Tag(
      title: title ?? file.tags?.title,
      trackArtist: artist ?? file.tags?.trackArtist,
      album: album ?? file.tags?.album,
      albumArtist: albumArtist ?? file.tags?.albumArtist,
      year: year != null ? int.tryParse(year) : file.tags?.year,
      genre: genre ?? file.tags?.genre,
      trackNumber: trackNumber != null ? int.tryParse(trackNumber) : file.tags?.trackNumber,
      trackTotal: file.tags?.trackTotal,
      discNumber: discNumber != null ? int.tryParse(discNumber) : file.tags?.discNumber,
      discTotal: file.tags?.discTotal,
      lyrics: file.tags?.lyrics,
      pictures: file.tags?.pictures ?? const [],
    );

    final success = await _tagService.writeTags(file, newTags);
    if (success) {
      final index = _files.indexOf(file);
      if (index != -1) {
        _files[index] = file.copyWith(tags: newTags);
        if (_selectedFile == file) {
          _selectedFile = _files[index];
        }
        notifyListeners();
      }
    }
  }

  Future<void> renameFile(AudioFile file, String newFilename) async {
    final newPath = await _fileService.renameFile(file, newFilename);
    if (newPath != null) {
      final index = _files.indexOf(file);
      if (index != -1) {
        _files[index] = file.copyWith(
          path: newPath,
          filename: newFilename, // Assuming newFilename includes extension or is handled
        );
        if (_selectedFile == file) {
          _selectedFile = _files[index];
        }
        notifyListeners();
      }
    }
  }
  
  Future<void> reloadFile(AudioFile file) async {
    final index = _files.indexOf(file);
    if (index != -1) {
      _files[index] = await _tagService.readTags(_files[index]);
      if (_selectedFile == file) {
        _selectedFile = _files[index];
      }
      notifyListeners();
    }
  }
  
  void setPendingCover(AudioFile file, List<int> coverBytes) {
    if (_isBatchMode && file == _batchTemplate) {
      _batchTemplate = _batchTemplate!.copyWith(pendingCover: coverBytes);
      notifyListeners();
      return;
    }
    
    final index = _files.indexOf(file);
    if (index != -1) {
      final updatedFile = _files[index].copyWith(pendingCover: coverBytes);
      _files[index] = updatedFile;
      
      if (_selectedFile?.path == file.path) {
        _selectedFile = updatedFile;
      }
      notifyListeners();
    }
  }
  
  void setPendingLyrics(AudioFile file, String lyrics) {
    final index = _files.indexOf(file);
    if (index != -1) {
      _files[index] = _files[index].copyWith(pendingLyrics: lyrics);
      if (_selectedFile == file) {
        _selectedFile = _files[index];
      }
      notifyListeners();
    }
  }

  void clearPendingLyrics(AudioFile file) {
    final index = _files.indexOf(file);
    if (index != -1) {
      _files[index] = _files[index].copyWith(clearPendingLyrics: true);
      if (_selectedFile == file) {
        _selectedFile = _files[index];
      }
      notifyListeners();
    }
  }
  
  void setExtractLyrics(AudioFile file, bool extract) {
    final index = _files.indexOf(file);
    if (index != -1) {
      _files[index] = _files[index].copyWith(extractLyrics: extract);
      if (_selectedFile == file) {
        _selectedFile = _files[index];
      }
      notifyListeners();
    }
  }

  bool _isFetchingLyrics = false;
  bool get isFetchingLyrics => _isFetchingLyrics;


  Future<void> setRomanizeLyrics(AudioFile file, bool romanize) async {
    final index = _files.indexOf(file);
    if (index != -1) {
      _isLoading = true;
      notifyListeners();

      try {
        final updatedFile = _files[index].copyWith(romanizeLyrics: romanize);
        _files[index] = updatedFile;
        
        if (_selectedFile?.path == file.path) {
          _selectedFile = updatedFile;
        }
        
        if (romanize) {
           final currentLyrics = updatedFile.pendingLyrics ?? updatedFile.tags?.lyrics ?? '';
           if (currentLyrics.isNotEmpty) {
             final result = await _romanizationService.romanize(currentLyrics);
             if (result != null) {
               setPendingLyrics(updatedFile, result);
             }
           }
        } else {
           clearPendingLyrics(updatedFile);
        }
      } catch (e) {
        print('Error in setRomanizeLyrics: $e');
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }
  }
  
  Future<bool> savePendingChanges(AudioFile file) async {
    bool success = true;
    
    Tag? currentTags = file.tags;
    if (currentTags == null) {
      try {
        currentTags = await _tagService.readTags(file).then((f) => f.tags);
      } catch (e) {
        print('Error reading tags: $e');
      }
    }

    String? lyricsToSave = file.pendingLyrics;
    
    if (file.romanizeLyrics) {
      final sourceLyrics = file.pendingLyrics ?? currentTags?.lyrics;
      if (sourceLyrics != null) {
        final romanized = await _romanizationService.romanize(sourceLyrics);
        if (romanized != null) {
          lyricsToSave = romanized;
          file = file.copyWith(pendingLyrics: romanized);
        }
      }
    } else if (file.pendingLyrics == null) {
        lyricsToSave = currentTags?.lyrics;
    }

    List<Picture>? picturesToSave = currentTags?.pictures;
    if (file.pendingCover != null) {
      picturesToSave = [
        Picture(
          pictureType: PictureType.coverFront,
          mimeType: MimeType.jpeg,
          bytes: Uint8List.fromList(file.pendingCover!),
        )
      ];
    }

    if (lyricsToSave != currentTags?.lyrics || file.pendingCover != null) {
        final newTag = Tag(
            title: currentTags?.title,
            trackArtist: currentTags?.trackArtist,
            album: currentTags?.album,
            albumArtist: currentTags?.albumArtist,
            genre: currentTags?.genre,
            year: currentTags?.year,
            trackNumber: currentTags?.trackNumber,
            trackTotal: currentTags?.trackTotal,
            discNumber: currentTags?.discNumber,
            discTotal: currentTags?.discTotal,
            lyrics: lyricsToSave,
            pictures: picturesToSave ?? [],
        );

        final saveSuccess = await _tagService.writeTags(file, newTag);
        if (!saveSuccess) success = false;
    }
    
    if (file.extractLyrics) {
      if (lyricsToSave != null && lyricsToSave.isNotEmpty) {
        final extractSuccess = await _fileService.extractLyricsToFile(file, lyricsToSave);
        if (!extractSuccess) success = false;
      }
    }
    
    if (success) {
      final index = _files.indexWhere((f) => f.path == file.path);
      if (index != -1) {
        _files[index] = _files[index].copyWith(
          clearPendingCover: true,
          clearPendingLyrics: true,
          extractLyrics: false, // Reset flags
          romanizeLyrics: false,
        );
        _files[index] = await _tagService.readTags(_files[index]);
        
        if (_selectedFile?.path == file.path) {
          _selectedFile = _files[index];
        }
        notifyListeners();
      }
    }
    
    return success;
  }

  void updateBatchTemplate({
    String? artist,
    String? album,
    String? albumArtist,
    String? year,
    String? genre,
  }) {
    if (_batchTemplate == null) return;
    
    final currentTags = _batchTemplate!.tags;
    final newTags = Tag(
      title: currentTags?.title,
      trackArtist: artist ?? currentTags?.trackArtist,
      album: album ?? currentTags?.album,
      albumArtist: albumArtist ?? currentTags?.albumArtist,
      genre: genre ?? currentTags?.genre,
      year: year != null ? int.tryParse(year) : currentTags?.year,
      trackNumber: currentTags?.trackNumber,
      trackTotal: currentTags?.trackTotal,
      discNumber: currentTags?.discNumber,
      discTotal: currentTags?.discTotal,
      lyrics: currentTags?.lyrics,
      pictures: currentTags?.pictures ?? [],
    );
    
    _batchTemplate = _batchTemplate!.copyWith(tags: newTags);
    
    if (artist != null) _batchDirtyFields.add('artist');
    if (album != null) _batchDirtyFields.add('album');
    if (albumArtist != null) _batchDirtyFields.add('albumArtist');
    if (year != null) _batchDirtyFields.add('year');
    if (genre != null) _batchDirtyFields.add('genre');
    
    notifyListeners();
  }

  void setBatchRomanize(bool romanize) {
    if (_batchTemplate == null) return;
    _batchTemplate = _batchTemplate!.copyWith(romanizeLyrics: romanize);
    notifyListeners();
  }

  void setBatchExtract(bool extract) {
    if (_batchTemplate == null) return;
    _batchTemplate = _batchTemplate!.copyWith(extractLyrics: extract);
    notifyListeners();
  }


  
  void discardPendingChanges(AudioFile file) {
    final index = _files.indexOf(file);
    if (index != -1) {
      _files[index] = _files[index].copyWith(
        clearPendingCover: true,
        clearPendingLyrics: true,
      );
      if (_selectedFile == file) {
        _selectedFile = _files[index];
      }
      notifyListeners();
    }
  }
  
  Future<void> convertSelectedToWav() async {
  }

  Future<void> deleteItem(dynamic item) async {
    bool success = false;
    if (item is AudioFile) {
      success = await _fileService.deleteFile(item.path);
    } else if (item is DirectoryItem) {
      success = await _fileService.deleteDirectory(item.path);
    }

    if (success) {
      if (_currentDirectory != null) {
        await navigateToDirectory(_currentDirectory!);
      }
      
      if (item is AudioFile && _selectedFile?.path == item.path) {
        _selectedFile = null;
        notifyListeners();
      }
    }
  }
}
