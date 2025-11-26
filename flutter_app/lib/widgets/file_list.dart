import 'package:flutter/material.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../providers/app_state.dart';
import '../models/directory_item.dart';
import '../models/audio_file.dart';
import 'breadcrumb_widget.dart';

import 'dart:typed_data';

class FileList extends StatelessWidget {
  const FileList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return Column(
          children: [
            const BreadcrumbWidget(),
            
            Expanded(
              child: _buildList(context, state),
            ),
          ],
        );
      },
    );
  }

  Widget _buildList(BuildContext context, AppState state) {
    if (state.isLoading && !state.isBatchMode) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<dynamic> items = [];
    
    if (state.isBatchMode) {
      items.addAll(state.batchFiles);
    } else {
      for (final dir in state.subdirectories) {
        items.add(DirectoryItem.fromDirectory(
          dir.path,
          p.basename(dir.path),
        ));
      }
      for (final file in state.filteredFiles) {
        items.add(DirectoryItem.fromAudioFile(file));
      }
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 80, color: Theme.of(context).colorScheme.outline.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              'This folder is empty',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
                if (selectedDirectory != null) {
                  context.read<AppState>().scanDirectory(selectedDirectory);
                }
              },
              icon: const Icon(Icons.create_new_folder),
              label: const Text('Open Folder'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        
        if (item is DirectoryItem && item.isDirectory) {
          return Card(
            margin: EdgeInsets.zero,
            color: Theme.of(context).colorScheme.surfaceContainer,
          child: GestureDetector(
            onSecondaryTapUp: (details) {
              _showContextMenu(context, details.globalPosition, item);
            },
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.folder,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              title: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                context.read<AppState>().navigateToDirectory(item.path);
              },
            ),
          ),
          );
        } 
        
        final AudioFile file = (item is DirectoryItem) ? item.audioFile! : item as AudioFile;
        final isSelected = state.selectedFile?.path == file.path;
        final hasLyrics = file.pendingLyrics != null || (file.tags?.lyrics != null && file.tags!.lyrics!.isNotEmpty);
        final isRomanized = (file.pendingLyrics != null && state.batchTemplate?.romanizeLyrics == true) || 
                            (file.romanizeLyrics);
        
        return Card(
          margin: EdgeInsets.zero,
          elevation: isSelected ? 0 : 0, // M3 lists usually flat or low elevation
          color: isSelected 
              ? Theme.of(context).colorScheme.secondaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isSelected 
                ? BorderSide.none // M3 uses color change for selection, not border
                : BorderSide.none,
          ),
          child: GestureDetector(
            onSecondaryTapUp: (details) {
              _showContextMenu(context, details.globalPosition, file);
            },
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Hero(
                    tag: file.path,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        image: (file.pendingCover != null || (file.tags?.pictures.isNotEmpty ?? false))
                            ? DecorationImage(
                                image: file.pendingCover != null
                                    ? MemoryImage(Uint8List.fromList(file.pendingCover!))
                                    : MemoryImage(file.tags!.pictures.first.bytes) as ImageProvider,
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: (file.pendingCover == null && (file.tags?.pictures.isEmpty ?? true))
                          ? Icon(Icons.audio_file, color: Theme.of(context).colorScheme.onSurfaceVariant)
                          : null,
                    ),
                  ),
                  title: Text(
                    file.tags?.title ?? file.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Theme.of(context).colorScheme.onSecondaryContainer : null,
                    ),
                  ),
                  subtitle: state.isBatchMode && (file.isProcessing || file.batchStatus != null)
                      ? null // Hide subtitle to show progress bar below
                      : Row(
                          children: [
                            Expanded(
                              child: Text(
                                file.tags?.trackArtist ?? 'Unknown Artist',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasLyrics)
                        Tooltip(
                          message: 'Lyrics Found',
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.lyrics, size: 14, color: Colors.green),
                          ),
                        ),
                      if (isRomanized)
                         Tooltip(
                          message: 'Romanized',
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Text('文', style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      if (file.hasPendingChanges)
                        Tooltip(
                          message: 'Pending Changes',
                          child: Icon(Icons.edit, size: 16, color: Theme.of(context).colorScheme.tertiary),
                        ),
                    ],
                  ),
                  onTap: () {
                    context.read<AppState>().selectFile(file);
                  },
                ),
                
                if (state.isBatchMode && (file.isProcessing || file.batchStatus != null))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(64, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (file.isProcessing)
                          const LinearProgressIndicator(minHeight: 2),
                        const SizedBox(height: 4),
                        Text(
                          file.batchStatus ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            color: file.batchStatus == 'Error' || file.batchStatus == 'Not Found' 
                                ? Theme.of(context).colorScheme.error 
                                : Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }


  void _showContextMenu(BuildContext context, Offset position, dynamic item) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'open_folder',
          child: Row(
            children: [
              Icon(Icons.folder_open, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Show in Folder', 
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 8),
              Text(
                'Delete', 
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'delete') {
        _confirmDelete(context, item);
      } else if (value == 'open_folder') {
        _openInFileExplorer(context, item);
      }
    });
  }

  void _confirmDelete(BuildContext context, dynamic item) {
    final isDirectory = item is DirectoryItem;
    final name = isDirectory ? item.name : (item as AudioFile).filename;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: Text(
          isDirectory 
              ? 'This will permanently delete this folder and all its contents. This action cannot be undone.'
              : 'This will permanently delete this file. This action cannot be undone.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AppState>().deleteItem(item);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }


  void _openInFileExplorer(BuildContext context, dynamic item) {
    String path = item is DirectoryItem ? item.path : (item as AudioFile).path;
    
    if (Theme.of(context).platform == TargetPlatform.linux) {
      Process.run('xdg-open', [p.dirname(path)]);
    } else if (Theme.of(context).platform == TargetPlatform.windows) {
      Process.run('explorer.exe', ['/select,', path]);
    } else if (Theme.of(context).platform == TargetPlatform.macOS) {
      Process.run('open', ['-R', path]);
    }
  }
}
