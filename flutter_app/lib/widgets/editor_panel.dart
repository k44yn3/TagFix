import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/audio_file.dart';
import '../providers/app_state.dart';
import '../services/ffmpeg_service.dart';
import 'cover_art_widget.dart';
import 'lyrics_widget.dart';

class EditorPanel extends StatefulWidget {
  final AudioFile file;

  const EditorPanel({super.key, required this.file});

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> {
  late TextEditingController _filenameController;
  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _albumController;
  late TextEditingController _yearController;
  late TextEditingController _genreController;
  late TextEditingController _trackController;
  late TextEditingController _discController;

  bool _hasUnsavedChanges = false;
  String? _conversionOutputPath;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void didUpdateWidget(covariant EditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _initControllers();
    } else if (oldWidget.file.hasPendingChanges != widget.file.hasPendingChanges) {
      _checkForChanges();
    }
  }

  void _initControllers() {
    final tags = widget.file.tags;
    _filenameController = TextEditingController(text: widget.file.filename);
    _titleController = TextEditingController(text: tags?.title ?? '');
    _artistController = TextEditingController(text: tags?.trackArtist ?? '');
    _albumController = TextEditingController(text: tags?.album ?? '');
    _yearController = TextEditingController(text: tags?.year?.toString() ?? '');
    _genreController = TextEditingController(text: tags?.genre ?? '');
    _trackController = TextEditingController(text: tags?.trackNumber?.toString() ?? '');
    _discController = TextEditingController(text: tags?.discNumber?.toString() ?? '');

    final controllers = [
      _filenameController, _titleController, _artistController, _albumController,
      _yearController, _genreController, _trackController, _discController
    ];
    for (final controller in controllers) {
      controller.addListener(_checkForChanges);
    }
    
    _checkForChanges();
  }

  void _checkForChanges() {
    final tags = widget.file.tags;
    bool hasChanges = false;

    if (_filenameController.text != widget.file.filename) hasChanges = true;
    if (_titleController.text != (tags?.title ?? '')) hasChanges = true;
    if (_artistController.text != (tags?.trackArtist ?? '')) hasChanges = true;
    if (_albumController.text != (tags?.album ?? '')) hasChanges = true;
    if (_yearController.text != (tags?.year?.toString() ?? '')) hasChanges = true;
    if (_genreController.text != (tags?.genre ?? '')) hasChanges = true;
    if (_trackController.text != (tags?.trackNumber?.toString() ?? '')) hasChanges = true;
    if (_discController.text != (tags?.discNumber?.toString() ?? '')) hasChanges = true;

    if (widget.file.hasPendingChanges) hasChanges = true;

    if (hasChanges != _hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = hasChanges);
    }
  }

  @override
  void dispose() {
    _filenameController.dispose();
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _yearController.dispose();
    _genreController.dispose();
    _trackController.dispose();
    _discController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_filenameController.text != widget.file.filename) {
       await context.read<AppState>().renameFile(widget.file, _filenameController.text);
    }

    await context.read<AppState>().updateTags(
      widget.file,
      title: _titleController.text,
      artist: _artistController.text,
      album: _albumController.text,
      year: _yearController.text,
      genre: _genreController.text,
      trackNumber: _trackController.text,
      discNumber: _discController.text,
    );
    
    final latestFile = context.read<AppState>().selectedFile;
    if (latestFile == null) return;
    
    await context.read<AppState>().savePendingChanges(latestFile);
    
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All changes saved permanently to file'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _convertToFlac() async {
    final appState = context.read<AppState>();
    
    if (appState.isBatchMode) {
       final confirm = await showDialog<bool>(
         context: context,
         builder: (context) => AlertDialog(
           title: const Text('Convert All to FLAC?'),
           content: Text('This will convert ${appState.batchTotalFiles} files to FLAC format. This process may take a while.'),
           actions: [
             TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
             FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Convert')),
           ],
         ),
       );
       
       if (confirm == true && mounted) {
         await appState.batchConvertToFlac();
         if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Batch conversion completed')),
            );
         }
       }
       return;
    }

    setState(() {
      _conversionOutputPath = null;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Converting to FLAC...')),
    );
    
    final result = await FfmpegService().convertToFlac(widget.file);
    
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (result != null) {
        setState(() {
          _conversionOutputPath = result;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conversion successful')),
        );
        if (appState.currentDirectory != null) {
          appState.scanDirectory(appState.currentDirectory!);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conversion failed')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isBatch = appState.isBatchMode;
    
    final metadataFile = isBatch ? appState.batchTemplate! : widget.file;
    final visualFile = widget.file; // Always show the selected file's visuals

    String folderName = '';
    if (isBatch && appState.currentDirectory != null) {
      folderName = appState.breadcrumbSegments.isNotEmpty 
          ? appState.breadcrumbSegments.last 
          : 'Current Folder';
    }
    
    return Scaffold(
      extendBodyBehindAppBar: true, // Allow content to flow behind AppBar for Hero effect
      appBar: AppBar(
        title: Text(isBatch 
            ? 'Batch Edit: ${appState.batchTotalFiles} files' 
            : widget.file.filename),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.7),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (isBatch && !appState.isLoading) 
            ? () => appState.saveBatchChanges()
            : (_hasUnsavedChanges && !appState.isLoading ? _save : null),
        icon: appState.isLoading 
            ? const SizedBox(
                width: 24, 
                height: 24, 
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
              )
            : const Icon(Icons.save),
        label: Text(appState.isLoading ? 'Applying...' : 'Apply Changes'),
        elevation: 3, // M3 Standard FAB elevation
        backgroundColor: (isBatch || _hasUnsavedChanges) && !appState.isLoading
            ? Theme.of(context).colorScheme.primaryContainer 
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: (isBatch || _hasUnsavedChanges) && !appState.isLoading
            ? Theme.of(context).colorScheme.onPrimaryContainer
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeroHeader(context, visualFile),
            
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isBatch)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).colorScheme.tertiary.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Theme.of(context).colorScheme.onTertiaryContainer),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Editing all files in "$folderName". Unique fields are hidden.',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onTertiaryContainer,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  _buildSectionTitle(context, 'Track Information'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (!isBatch) ...[
                            TextField(
                              controller: _filenameController,
                              decoration: const InputDecoration(labelText: 'Filename', prefixIcon: Icon(Icons.file_present)),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _titleController,
                              decoration: const InputDecoration(labelText: 'Title', prefixIcon: Icon(Icons.title)),
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextField(
                            controller: _artistController,
                            decoration: const InputDecoration(labelText: 'Artist', prefixIcon: Icon(Icons.person)),
                            onChanged: isBatch ? (val) => appState.updateBatchTemplate(artist: val) : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  _buildSectionTitle(context, 'Album Details'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextField(
                            controller: _albumController,
                            decoration: const InputDecoration(labelText: 'Album', prefixIcon: Icon(Icons.album)),
                            onChanged: isBatch ? (val) => appState.updateBatchTemplate(album: val) : null,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _yearController,
                                  decoration: const InputDecoration(labelText: 'Year', prefixIcon: Icon(Icons.calendar_today)),
                                  keyboardType: TextInputType.number,
                                  onChanged: isBatch ? (val) => appState.updateBatchTemplate(year: val) : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _genreController,
                                  decoration: const InputDecoration(labelText: 'Genre', prefixIcon: Icon(Icons.category)),
                                  onChanged: isBatch ? (val) => appState.updateBatchTemplate(genre: val) : null,
                                ),
                              ),
                            ],
                          ),
                          if (!isBatch) ...[
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _trackController,
                                    decoration: const InputDecoration(labelText: 'Track No.', prefixIcon: Icon(Icons.numbers)),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _discController,
                                    decoration: const InputDecoration(labelText: 'Disc No.', prefixIcon: Icon(Icons.album_outlined)),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  _buildSectionTitle(context, 'Lyrics'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: LyricsWidget(file: visualFile),
                    ),
                  ),
                  
                  const SizedBox(height: 24),

                  _buildSectionTitle(context, 'Format Conversion'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isBatch 
                                ? 'Convert all ${appState.batchTotalFiles} files to FLAC.'
                                : 'Convert to FLAC',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _convertToFlac,
                              icon: const Icon(Icons.audiotrack),
                              label: Text(isBatch ? 'Convert All to FLAC' : 'Convert to FLAC'),
                            ),
                          ),
                          if (_conversionOutputPath != null && !isBatch) ...[
                            const SizedBox(height: 16),
                            InkWell(
                              onTap: () {
                                final path = _conversionOutputPath!;
                                if (Theme.of(context).platform == TargetPlatform.linux) {
                                  Process.run('xdg-open', [path]);
                                } else if (Theme.of(context).platform == TargetPlatform.windows) {
                                  Process.run('explorer.exe', [path]);
                                } else if (Theme.of(context).platform == TargetPlatform.macOS) {
                                  Process.run('open', [path]);
                                }
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.folder_open, 
                                      size: 20, 
                                      color: Theme.of(context).colorScheme.primary
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Output Directory (Click to Open):',
                                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                              color: Theme.of(context).colorScheme.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            _conversionOutputPath!,
                                            style: Theme.of(context).textTheme.bodySmall,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.open_in_new, 
                                      size: 16, 
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.7)
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 80), // Space for FAB
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context, AudioFile file) {
    return SizedBox(
      height: 300,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (file.pendingCover != null || (file.tags?.pictures.isNotEmpty ?? false))
             Image(
                image: file.pendingCover != null
                    ? MemoryImage(Uint8List.fromList(file.pendingCover!))
                    : MemoryImage(file.tags!.pictures.first.bytes) as ImageProvider,
                fit: BoxFit.cover,
                color: Colors.black.withOpacity(0.6),
                colorBlendMode: BlendMode.darken,
             )
          else
            Container(
              color: Theme.of(context).colorScheme.surfaceContainer,
            ),
            
          BackdropFilter(
            filter:  ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(color: Colors.transparent),
          ),
          
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40), // AppBar spacing
                Hero(
                  tag: file.path,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CoverArtWidget(file: file),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
