import 'package:audiotags/audiotags.dart';

class AudioFile {
  final String path;
  final String filename;
  final Tag? tags;
  final int? duration; // Duration in seconds
  final bool isSelected;
  final bool hasError;
  final String? errorMessage;
  
  final List<int>? pendingCover;
  final String? pendingLyrics;
  final bool extractLyrics;
  final bool romanizeLyrics;

  final String? batchStatus;
  final bool isProcessing;

  const AudioFile({
    required this.path,
    required this.filename,
    this.tags,
    this.duration,
    this.isSelected = false,
    this.hasError = false,
    this.errorMessage,
    this.pendingCover,
    this.pendingLyrics,
    this.extractLyrics = false,
    this.romanizeLyrics = false,
    this.batchStatus,
    this.isProcessing = false,
  });
  
  bool get hasPendingChanges => pendingCover != null || pendingLyrics != null || extractLyrics || romanizeLyrics;


  AudioFile copyWith({
    String? path,
    String? filename,
    Tag? tags,
    int? duration,
    bool? isSelected,
    bool? hasError,
    String? errorMessage,
    List<int>? pendingCover,
    String? pendingLyrics,
    bool? extractLyrics,
    bool? romanizeLyrics,
    String? batchStatus,
    bool? isProcessing,
    bool clearPendingCover = false,
    bool clearPendingLyrics = false,
  }) {
    return AudioFile(
      path: path ?? this.path,
      filename: filename ?? this.filename,
      tags: tags ?? this.tags,
      duration: duration ?? this.duration,
      isSelected: isSelected ?? this.isSelected,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
      pendingCover: clearPendingCover ? null : (pendingCover ?? this.pendingCover),
      pendingLyrics: clearPendingLyrics ? null : (pendingLyrics ?? this.pendingLyrics),
      extractLyrics: extractLyrics ?? this.extractLyrics,
      romanizeLyrics: romanizeLyrics ?? this.romanizeLyrics,
      batchStatus: batchStatus ?? this.batchStatus,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }
}
