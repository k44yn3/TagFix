import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../services/musicbrainz_service.dart';

class CoverSearchDialog extends StatefulWidget {
  final String initialArtist;
  final String initialAlbum;

  const CoverSearchDialog({
    super.key,
    required this.initialArtist,
    required this.initialAlbum,
  });

  @override
  State<CoverSearchDialog> createState() => _CoverSearchDialogState();
}

class _CoverSearchDialogState extends State<CoverSearchDialog> {
  late TextEditingController _artistController;
  late TextEditingController _albumController;
  final MusicBrainzService _service = MusicBrainzService();
  
  List<MusicBrainzRelease>? _searchResults;
  bool _isSearching = false;
  String? _errorMessage;
  MusicBrainzRelease? _selectedRelease;
  Uint8List? _coverPreview;
  bool _isLoadingCover = false;

  @override
  void initState() {
    super.initState();
    _artistController = TextEditingController(text: widget.initialArtist);
    _albumController = TextEditingController(text: widget.initialAlbum);
  }

  @override
  void dispose() {
    _artistController.dispose();
    _albumController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_artistController.text.isEmpty || _albumController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both artist and album';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _searchResults = null;
      _selectedRelease = null;
      _coverPreview = null;
    });

    try {
      final results = await _service.searchReleases(
        artist: _artistController.text,
        album: _albumController.text,
      );

      setState(() {
        _isSearching = false;
        if (results.isEmpty) {
          _errorMessage = 'No releases found. Try adjusting your search terms.';
        } else {
          _searchResults = results;
          if (results.isNotEmpty) {
            _selectRelease(results.first);
          }
        }
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _errorMessage = 'Error searching: $e';
      });
    }
  }

  Future<void> _selectRelease(MusicBrainzRelease release) async {
    setState(() {
      _selectedRelease = release;
      _isLoadingCover = true;
      _coverPreview = null;
    });

    try {
      final coverData = await _service.getCoverArt(release.id);
      if (coverData != null && mounted) {
        setState(() {
          _coverPreview = Uint8List.fromList(coverData);
          _isLoadingCover = false;
        });
      } else if (mounted) {
        setState(() {
          _isLoadingCover = false;
          _errorMessage = 'No cover art available for this release';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingCover = false;
          _errorMessage = 'Error loading cover: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('Search Cover Art Online'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Edit search metadata:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _artistController,
                    decoration: const InputDecoration(
                      labelText: 'Artist',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _albumController,
                    decoration: const InputDecoration(
                      labelText: 'Album',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.album),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  FilledButton.icon(
                    onPressed: _isSearching ? null : _search,
                    icon: _isSearching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: Text(_isSearching ? 'Searching...' : 'Search MusicBrainz'),
                  ),
                  
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Theme.of(context).colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  
                  if (_searchResults != null && _searchResults!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 12),
                    const Text(
                      'Search Results:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    
                    ..._searchResults!.map((release) => ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Card(
                        color: _selectedRelease?.id == release.id
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        child: ListTile(
                          title: Text(release.title),
                          subtitle: Text(release.displayName),
                          leading: const Icon(Icons.album),
                          selected: _selectedRelease?.id == release.id,
                          onTap: () => _selectRelease(release),
                        ),
                      ),
                    )),
                    
                    if (_selectedRelease != null) ...[
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 12),
                      const Text(
                        'Cover Preview:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: _isLoadingCover
                            ? const CircularProgressIndicator()
                            : _coverPreview != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(
                                      _coverPreview!,
                                      width: 300,
                                      height: 300,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Text('No cover art available'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _coverPreview != null
                        ? () => Navigator.pop(context, _coverPreview)
                        : null,
                    child: const Text('Apply Cover'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
