import 'package:flutter/material.dart';
import 'package:audiotags/audiotags.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:typed_data';
import '../models/audio_file.dart';
import '../services/tag_service.dart';
import '../services/musicbrainz_service.dart';
import '../providers/app_state.dart';
import 'cover_search_dialog.dart';
import '../services/image_service.dart';

class CoverArtWidget extends StatelessWidget {
  final AudioFile file;

  const CoverArtWidget({super.key, required this.file});
  
  Future<void> _showOptionsDialog(BuildContext context) async {
    final option = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Cover Art'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Select from file'),
              subtitle: const Text('Choose an image from your device'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.cloud_download),
              title: const Text('Fetch online'),
              subtitle: const Text('Search MusicBrainz for cover art'),
              onTap: () => Navigator.pop(context, 'online'),
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

    if (option == 'file') {
      await _selectFromFile(context);
    } else if (option == 'online') {
      await _fetchOnline(context);
    }
  }
  
  Future<void> _selectFromFile(BuildContext context) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );

    if (result != null && context.mounted) {
      File imageFile = File(result.files.single.path!);
      final bytes = await imageFile.readAsBytes();
      await _applyCover(context, bytes);
    }
  }
  
  
  Future<void> _fetchOnline(BuildContext context) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final isBatch = appState.isBatchMode;
    
    if (isBatch) {
      bool replaceExisting = false;
      
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Batch Fetch Covers'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('This will search for unique covers for all ${appState.batchTotalFiles} files using their metadata (Artist/Album).'),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Replace existing covers'),
                  subtitle: const Text('Overwrite current art if new cover is found'),
                  value: replaceExisting,
                  onChanged: (value) {
                    setState(() {
                      replaceExisting = value ?? false;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Start Fetching'),
              ),
            ],
          ),
        ),
      );
      
      if (confirm == true && context.mounted) {
        appState.batchFetchCovers(replaceExisting: replaceExisting);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Batch cover fetch started...')),
        );
      }
      return;
    }

    String artist = '';
    String album = '';
    
    
    artist = file.tags?.trackArtist ?? '';
    album = file.tags?.album ?? '';
    
    if (artist.isEmpty || album.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Artist and Album metadata required for online search'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    
    final coverData = await showDialog<Uint8List>(
      context: context,
      builder: (context) => CoverSearchDialog(
        initialArtist: artist,
        initialAlbum: album,
      ),
    );
    
    if (coverData != null && context.mounted) {
      await _applyCover(context, coverData);
    }
  }
  
  
  
  Future<void> _applyCover(BuildContext context, List<int> bytes) async {
    if (context.mounted) {
      final appState = Provider.of<AppState>(context, listen: false);
      
      final isBatch = appState.isBatchMode;
      
      if (isBatch) {
        if (appState.batchTemplate != null) {
          appState.setPendingCover(appState.batchTemplate!, bytes);
        }
      } else {
        appState.setPendingCover(file, bytes);
      }
      
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isBatch 
              ? "Cover will be applied to all files when you click 'Apply Changes'."
              : "Preview applied. Click 'Apply Changes' to save."),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isBatch = appState.isBatchMode;
    
    
    bool hasPendingCover = false;
    List<int>? pendingCoverBytes;
    Picture? referenceCover;
    
    if (isBatch) {
      
      if (file == appState.batchTemplate) {
         if (appState.batchTemplate?.pendingCover != null) {
          hasPendingCover = true;
          pendingCoverBytes = appState.batchTemplate!.pendingCover!;
        }
      } else {
        if (file.pendingCover != null) {
          hasPendingCover = true;
          pendingCoverBytes = file.pendingCover!;
        } else if (appState.batchTemplate?.pendingCover != null) {
           hasPendingCover = true;
           pendingCoverBytes = appState.batchTemplate!.pendingCover!;
        }
      }

      if (!hasPendingCover) {
        if (file.tags?.pictures != null && file.tags!.pictures!.isNotEmpty) {
          referenceCover = file.tags!.pictures!.first;
        }
      }
    } else {
      hasPendingCover = file.pendingCover != null;
      if (hasPendingCover) {
        pendingCoverBytes = file.pendingCover!;
      } else if (file.tags?.pictures != null && file.tags!.pictures!.isNotEmpty) {
        referenceCover = file.tags!.pictures!.first;
      }
    }
    
    final hasCover = hasPendingCover || referenceCover != null;

    return GestureDetector(
      onTap: () => _showOptionsDialog(context),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Stack(
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasPendingCover 
                      ? Theme.of(context).colorScheme.primary  // Highlight pending
                      : Theme.of(context).colorScheme.outline.withOpacity(0.5),
                  width: hasPendingCover ? 3 : 2,
                ),
                image: hasCover
                    ? DecorationImage(
                        image: MemoryImage(
                          hasPendingCover 
                              ? Uint8List.fromList(pendingCoverBytes!)
                              : referenceCover!.bytes
                        ),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: !hasCover
                  ? Icon(
                      Icons.music_note,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )
                  : null,
            ),
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.edit,
                  size: 20,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            
            if (hasCover)
              Positioned(
                bottom: 8,
                left: 8,
                child: GestureDetector(
                  onTap: () async {
                    final currentBytes = hasPendingCover 
                        ? pendingCoverBytes!
                        : referenceCover!.bytes;
                        
                    final imageService = ImageService();
                    final resizedBytes = await imageService.resizeImage(currentBytes);
                    
                    if (resizedBytes != null && context.mounted) {
                      await _applyCover(context, resizedBytes);
                      
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cover resized to 500x500 (Preview)'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.compress,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Resize',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
