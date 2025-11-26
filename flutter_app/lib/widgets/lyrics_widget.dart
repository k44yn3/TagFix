import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/audio_file.dart';
import '../services/tag_service.dart';
import '../services/romanization_service.dart';
import '../providers/app_state.dart';
import 'lyrics_edit_dialog.dart';

class LyricsWidget extends StatefulWidget {
  final AudioFile file;

  const LyricsWidget({super.key, required this.file});

  @override
  State<LyricsWidget> createState() => _LyricsWidgetState();
}

class _LyricsWidgetState extends State<LyricsWidget> {
  String? _lyrics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }


  @override
  void didUpdateWidget(covariant LyricsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path || 
        oldWidget.file.tags != widget.file.tags ||
        oldWidget.file.pendingLyrics != widget.file.pendingLyrics) {
      _loadLyrics();
    }
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadLyrics();
  }


  Future<void> _loadLyrics() async {
    final appState = context.read<AppState>();
    final isBatch = appState.isBatchMode;
    
    if (isBatch) {
      if (widget.file.pendingLyrics != null) {
        if (mounted) {
          setState(() {
            _lyrics = widget.file.pendingLyrics;
            _isLoading = false;
          });
        }
        return;
      }

      
      
      
      if (widget.file == appState.batchTemplate && appState.batchTemplate?.pendingLyrics != null) {
         if (mounted) {
          setState(() {
            _lyrics = appState.batchTemplate!.pendingLyrics;
            _isLoading = false;
          });
        }
        return;
      }
      
      setState(() => _isLoading = true);
      final tagService = TagService();
      final lyrics = await tagService.getLyrics(widget.file);
      if (mounted) {
        setState(() {
          _lyrics = lyrics;
          _isLoading = false;
        });
      }
      return;
    }
    
    if (widget.file.pendingLyrics != null) {
      if (mounted) {
        setState(() {
          _lyrics = widget.file.pendingLyrics;
          _isLoading = false;
        });
      }
      return;
    }

    setState(() => _isLoading = true);
    final tagService = TagService();
    final lyrics = await tagService.getLyrics(widget.file);
    if (mounted) {
      setState(() {
        _lyrics = lyrics;
        _isLoading = false;
      });
    }
  }

  Future<void> _editLyrics() async {
    final initialLyrics = widget.file.pendingLyrics ?? _lyrics ?? '';
    
    await showLyricsEditDialog(
      context,
      widget.file,
      initialLyrics,
    );
    
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isBatch = appState.isBatchMode;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text(
                  'Lyrics',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (!isBatch) ...[
                  const SizedBox(width: 16),
                  Checkbox(
                    value: widget.file.extractLyrics,
                    onChanged: (value) {
                      context.read<AppState>().setExtractLyrics(widget.file, value ?? false);
                    },
                  ),
                  const Text('Copy and Rename'),
                ],
              ],
            ),
            Row(
              children: [
                if (isBatch) ...[
                  Checkbox(
                    value: appState.batchTemplate?.extractLyrics ?? false,
                    onChanged: (value) {
                      context.read<AppState>().setBatchExtract(value ?? false);
                    },
                  ),
                  const Text('Copy and Rename'),
                  const SizedBox(width: 16),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<bool>(
                      value: isBatch 
                          ? (appState.batchTemplate?.romanizeLyrics ?? false)
                          : widget.file.romanizeLyrics,
                      icon: const Icon(Icons.translate),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: false, 
                          child: Text('Original Lyrics'),
                        ),
                        DropdownMenuItem(
                          value: true, 
                          child: Text('Romanize (Korean)'),
                        ),
                      ],
                      onChanged: (value) {
                        if (isBatch) {
                          context.read<AppState>().setBatchRomanize(value ?? false);
                        } else {
                          context.read<AppState>().setRomanizeLyrics(widget.file, value ?? false);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (isBatch)
                  FilledButton.tonalIcon(
                    onPressed: appState.isLoading ? null : () => appState.batchFetchLyrics(),
                    icon: appState.isFetchingLyrics 
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download),
                    label: const Text('Fetch All'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: _editLyrics,
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Lyrics'),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(
              color: widget.file.pendingLyrics != null
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline.withOpacity(0.5),
              width: widget.file.pendingLyrics != null ? 3 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _lyrics == null || _lyrics!.isEmpty
                  ? Center(
                      child: Text(
                        'No lyrics',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        _lyrics!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.5,
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}
