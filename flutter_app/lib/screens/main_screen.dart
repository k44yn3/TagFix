import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/app_state.dart';
import '../widgets/file_list.dart';
import '../widgets/editor_panel.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final hasSelectedFile = appState.selectedFile != null;
    
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search by title, artist, or album...',
                  border: InputBorder.none,
                ),
                onChanged: (query) {
                  context.read<AppState>().setSearchQuery(query);
                },
              )
            : Row(
                children: [
                  const Text('TagFix'),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '@k44yn3 on Github',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
        actions: [
          if (!_isSearching) ...[
            Center(
              child: Text(
                'Powered by MusicBrainz & LRCLIB',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
          if (!hasSelectedFile)
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchController.clear();
                    context.read<AppState>().setSearchQuery(null);
                  }
                });
              },
              tooltip: _isSearching ? 'Close search' : 'Search files',
            ),

          const SizedBox(width: 8),
          if (appState.currentDirectory != null) ...[

            const SizedBox(width: 8),

            TextButton.icon(
              icon: Icon(appState.isBatchMode ? Icons.done_all : Icons.checklist),
              label: Text(appState.isBatchMode ? 'Exit Batch' : 'Batch Edit'),
              style: TextButton.styleFrom(
                backgroundColor: appState.isBatchMode 
                    ? Theme.of(context).colorScheme.tertiaryContainer 
                    : null,
                foregroundColor: appState.isBatchMode 
                    ? Theme.of(context).colorScheme.onTertiaryContainer 
                    : null,
              ),
              onPressed: () async {
                final newBatchMode = !appState.isBatchMode;
                appState.toggleBatchMode(newBatchMode);
                
                if (newBatchMode) {
                  if (appState.batchFiles.isNotEmpty) {
                     appState.selectFile(appState.batchFiles.first);
                  }
                }
              },
            ),
            const SizedBox(width: 8),
          ],
          if (appState.currentDirectory != null && !hasSelectedFile)
            TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              onPressed: () {
                final currentDir = context.read<AppState>().currentDirectory;
                if (currentDir != null) {
                  context.read<AppState>().navigateToDirectory(currentDir);
                }
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          const Expanded(
            flex: 1,
            child: FileList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 2,
            child: Consumer<AppState>(
              builder: (context, state, child) {
                if (state.selectedFile == null) {
                  return const Center(
                    child: Text('Select a file to edit metadata'),
                  );
                }
                return EditorPanel(file: state.selectedFile!);
              },
            ),
          ),
        ],
      ),
    );
  }
}
