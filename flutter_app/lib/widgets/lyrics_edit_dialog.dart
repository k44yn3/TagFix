import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../models/audio_file.dart';
import '../services/tag_service.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'lyrics_search_dialog.dart';

Future<bool?> showLyricsEditDialog(BuildContext context, AudioFile file, String initialLyrics) async {
  final option = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Edit Lyrics'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Import from file'),
            subtitle: const Text('Load lyrics from .lrc or .txt file'),
            onTap: () => Navigator.pop(context, 'import'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Edit directly'),
            subtitle: const Text('Type or paste lyrics'),
            onTap: () => Navigator.pop(context, 'edit'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cloud_download),
            title: const Text('Search Online'),
            subtitle: const Text('Fetch from LRCLIB'),
            onTap: () => Navigator.pop(context, 'search'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );

  if (option == null) return null;

  if (option == 'import') {
    return await _handleImport(context, file, initialLyrics);
  } else if (option == 'search') {
    return await _handleSearch(context, file, initialLyrics);
  } else {
    return await _handleDirectEdit(context, file, initialLyrics);
  }
}

Future<bool?> _handleSearch(BuildContext context, AudioFile file, String initialLyrics) async {
  final result = await showDialog<String>(
    context: context,
    builder: (context) => LyricsSearchDialog(
      initialArtist: file.tags?.trackArtist ?? file.tags?.albumArtist ?? '',
      initialTitle: file.tags?.title ?? '',
      initialAlbum: file.tags?.album ?? '',
    ),
  );

  if (result != null && context.mounted) {
    return await _showEditDialog(
      context,
      file,
      result,
      importedFileName: 'Fetched from LRCLIB',
    );
  }
  return null;
}

Future<bool?> _handleImport(BuildContext context, AudioFile file, String initialLyrics) async {
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['lrc', 'txt'],
  );

  if (result == null || !context.mounted) return null;

  try {
    File lyricsFile = File(result.files.single.path!);
    final content = await lyricsFile.readAsString();
    final fileName = path.basename(lyricsFile.path);

    return await _showEditDialog(
      context,
      file,
      content,
      showCopyOption: true,
      sourceFile: lyricsFile.path,
      importedFileName: fileName,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error reading file: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    return null;
  }
}

Future<bool?> _handleDirectEdit(BuildContext context, AudioFile file, String initialLyrics) async {
  return await _showEditDialog(context, file, initialLyrics);
}

Future<bool?> _showEditDialog(
  BuildContext context,
  AudioFile file,
  String initialLyrics, {
  bool showCopyOption = false,
  String? sourceFile,
  String? importedFileName,
}) async {
  final controller = TextEditingController(text: initialLyrics);
  bool copyToAudioFolder = false;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return Dialog(
          child: Container(
            width: 600,
            constraints: const BoxConstraints(maxHeight: 700),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBar(
                  title: const Text('Edit Lyrics'),
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (importedFileName != null) ...[
                          Card(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.file_present,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Imported: $importedFileName',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        const Text(
                          'Lyrics:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TextField(
                            controller: controller,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Enter lyrics here...',
                            ),
                          ),
                        ),
                        if (showCopyOption) ...[
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            value: copyToAudioFolder,
                            onChanged: (value) {
                              setState(() => copyToAudioFolder = value ?? false);
                            },
                            title: const Text('Copy lyrics file to audio folder'),
                            subtitle: const Text('Rename to match audio filename'),
                            dense: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          if (copyToAudioFolder && sourceFile != null) {
                            try {
                              final audioDir = path.dirname(file.path);
                              final audioBasename = path.basenameWithoutExtension(file.path);
                              final lyricsExt = path.extension(sourceFile);
                              final destPath = path.join(audioDir, '$audioBasename$lyricsExt');

                              if (path.normalize(sourceFile) != path.normalize(destPath)) {
                                await File(sourceFile).copy(destPath);

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).clearSnackBars();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Lyrics file copied to: $destPath'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              } else {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).clearSnackBars();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Lyrics file is already in the correct location'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).clearSnackBars();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error copying file: $e'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            }
                          }

                          if (context.mounted) {
                            final appState = Provider.of<AppState>(context, listen: false);
                            appState.setPendingLyrics(file, controller.text);
                            
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Preview applied. Click 'Apply Changes' to save."),
                                duration: Duration(seconds: 3),
                              ),
                            );
                            Navigator.pop(context, true);
                          }
                        },
                        child: const Text('Apply for Preview'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  controller.dispose();
  return result;
}
