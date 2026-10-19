import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/saved_papers_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/math_text.dart';

/// A searchable collection of papers the reader explicitly saved to revisit.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _storage = SavedPapersStorage();
  late Future<List<SavedPaperEntry>> _entriesFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _entriesFuture = _storage.load();
  }

  Future<void> _refresh() async {
    setState(() => _entriesFuture = _storage.load());
    await _entriesFuture;
  }

  Future<void> _remove(SavedPaperEntry entry) async {
    await _storage.remove(entry.paper.url);
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Removed from Library'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            _storage.save(entry.paper).then((_) => _refresh());
          },
        ),
      ),
    );
  }

  Future<void> _openPaper(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    final launchUri = uri.hasScheme ? uri : Uri.parse('https://$url');
    if (!await launchUrl(launchUri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the publication link')),
      );
    }
  }

  bool _matches(SavedPaperEntry entry) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    final paper = entry.paper;
    return '${paper.title} ${paper.authors} ${paper.journal} ${paper.sourceDisplayName}'
        .toLowerCase()
        .contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'LIBRARY',
          style: TextStyle(
            fontFamily: '-apple-system',
            fontWeight: FontWeight.w800,
            letterSpacing: 2.0,
            fontSize: 13,
            color: palette.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<List<SavedPaperEntry>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = (snapshot.data ?? const []).where(_matches).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search saved papers',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: palette.surfaceRaised,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: palette.borderSoft),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: palette.borderSoft),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? _EmptyLibrary(hasSearch: _query.trim().isNotEmpty)
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                          itemCount: entries.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) => _LibraryCard(
                            entry: entries[index],
                            onOpen: () => _openPaper(entries[index].paper.url),
                            onRemove: () => _remove(entries[index]),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final bool hasSearch;

  const _EmptyLibrary({required this.hasSearch});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 42,
              color: palette.textTertiary,
            ),
            const SizedBox(height: 14),
            Text(
              hasSearch
                  ? 'No saved papers match that search.'
                  : 'Your Library is ready for the papers you want to revisit.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: palette.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  final SavedPaperEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _LibraryCard({
    required this.entry,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final paper = entry.paper;
    final date = entry.savedAt.toLocal().toString().split(' ').first;
    return Material(
      color: palette.surfaceRaised,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: paper.url.isEmpty ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MathText(
                      paper.title,
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (paper.authors.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        paper.authors,
                        style: TextStyle(
                          fontSize: 14,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Saved $date${paper.journal.isEmpty ? '' : ' · ${paper.journal}'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove from Library',
                icon: Icon(
                  Icons.bookmark_remove_outlined,
                  color: palette.textSecondary,
                ),
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
