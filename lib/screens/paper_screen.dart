import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/paper.dart';
import '../models/streak_data.dart';
import '../models/user_profile.dart';
import '../services/dismissed_papers_storage.dart';
import '../services/feedback_storage.dart';
import '../services/interest_matcher.dart';
import '../services/liked_papers_storage.dart';
import '../services/paper_buffer_storage.dart';
import '../services/paper_history_storage.dart';
import '../services/paper_service.dart';
import '../services/local_recommendation_service.dart';
import '../services/profile_storage.dart';
import '../services/saved_papers_storage.dart';
import '../services/streak_service.dart';
import '../services/clock_skew.dart';
import '../widgets/shimmer_loader.dart';
import '../widgets/reveal.dart';
import '../widgets/press_button.dart';
import '../widgets/preprint_disclaimer.dart';
import '../widgets/paper_header.dart';
import '../widgets/math_text.dart';
import '../widgets/streak_badge.dart';
import '../widgets/streak_celebration.dart';
import '../theme/app_theme.dart';
import 'history_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';

class PaperScreen extends StatefulWidget {
  const PaperScreen({super.key});

  @override
  State<PaperScreen> createState() => _PaperScreenState();
}

class _PaperScreenState extends State<PaperScreen> with WidgetsBindingObserver {
  final _service = PaperService();
  final _recommendationService = LocalRecommendationService();
  final _profileStorage = ProfileStorage();
  final _historyStorage = PaperHistoryStorage();
  final _feedbackStorage = FeedbackStorage();
  final _likedStorage = LikedPapersStorage();
  final _savedPapersStorage = SavedPapersStorage();
  final _dismissedStorage = DismissedPapersStorage();
  final _bufferStorage = PaperBufferStorage();
  final _streakService = StreakService();

  UserProfile? _profile;
  List<String>? selectedSubjects;
  Paper? _paper;
  bool isLoading = true;
  bool hasError = false;
  String errorTitle = '';
  String errorMessage = '';

  // True when the paper currently on screen was served from the offline
  // buffer rather than a live fetch (either because the device had no
  // connection, or because the live fetch failed).
  bool _isOffline = false;

  // Tracks the calendar day the currently-shown paper was loaded on, so we
  // can detect "app was left open/backgrounded across midnight" and force
  // a refresh when it's noticed again (e.g. on resume).
  DateTime? _lastLoadedDay;

  Map<String, int> _dislikeCounts = {};
  String? _currentSubject;
  int _subjectRotationIndex = 0;
  int _attempt = 0;
  bool _isFetchingDaily = false;
  final Set<String> _shownUrlsToday = {};

  Set<String> _likedUrls = {};
  Set<String> _savedUrls = {};
  bool get _isCurrentLiked =>
      _paper != null && _likedUrls.contains(_paper!.url);
  bool get _isCurrentSaved =>
      _paper != null && _savedUrls.contains(_paper!.url);

  // Full streak state shown in the app bar badge. Refreshed after
  // evaluateOnOpen() and after every recordActivity() call. StreakBadge
  // needs the whole object (not just loose ints) because it renders the
  // weekly history tracker off streakData.history.
  StreakData _streakData = const StreakData();

  // Tracks the 1-continuous-minute-in-app session used to advance the
  // streak. Per spec, this timer resets (not pauses/resumes) whenever the
  // app leaves the foreground before hitting 60 seconds.
  Timer? _sessionTimer;
  bool _streakLoggedToday = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfileAndFetch();
    _loadLikedUrls();
    _loadSavedUrls();
    _initStreak();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForNewDay();
      _initStreak();
    } else {
      // App left the foreground before the 1-minute mark — per spec the
      // timer resets rather than pausing, so it starts fresh next time
      // the app is opened/resumed.
      _sessionTimer?.cancel();
      _sessionTimer = null;
    }
  }

  /// Resolves any missed days (freeze consumption / streak break) as soon
  /// as the app is opened or resumed, refreshes the badge state, shows
  /// the corresponding popup if something changed, and (re)starts the
  /// 1-minute session timer that drives today's streak increment.
  Future<void> _initStreak() async {
    final result = await _streakService.evaluateOnOpen();
    final data = await _streakService.getStreakData();
    if (!mounted) return;
    setState(() {
      _streakData = data;
    });

    if (result.freezeConsumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showFreezeUsedPopup(context, currentStreak: result.currentStreak);
        }
      });
    } else if (result.streakBroken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showStreakBrokenPopup(context, previousStreak: result.previousStreak);
        }
      });
    }

    _streakLoggedToday = await _streakService.hasLoggedToday();
    if (!mounted) return;
    _sessionTimer?.cancel();
    if (!_streakLoggedToday) {
      _sessionTimer = Timer(
        const Duration(minutes: 1),
        _onSessionThresholdReached,
      );
    }
  }

  /// Fired once the user has been continuously in the foreground for 1
  /// minute on a day the streak hasn't been logged for yet.
  Future<void> _onSessionThresholdReached() async {
    _sessionTimer = null;
    final result = await _streakService.recordActivity();
    final data = await _streakService.getStreakData();
    if (!mounted) return;
    _streakLoggedToday = true;
    setState(() {
      _streakData = data;
    });

    await showStreakIncreasedPopup(
      context,
      oldStreak: result.previousStreak,
      newStreak: result.currentStreak,
    );
    if (result.milestoneHit != null && mounted) {
      await showMilestonePopup(context, milestoneDays: result.milestoneHit!);
    }
  }

  /// Marks the currently loaded paper as belonging to "today", using the
  /// current wall-clock date.
  void _markLoadedToday() {
    _lastLoadedDay = DateTime.now();
  }

  /// Called whenever the app comes back to the foreground. If the paper
  /// on screen was loaded on a previous calendar day (e.g. the user kept
  /// the app open/backgrounded overnight instead of fully closing it),
  /// forces a fresh fetch so the recommendation updates without requiring
  /// a manual reload.
  void _checkForNewDay() {
    if (_lastLoadedDay == null || isLoading) return;

    final now = DateTime.now();
    final sameDay =
        _lastLoadedDay!.year == now.year &&
        _lastLoadedDay!.month == now.month &&
        _lastLoadedDay!.day == now.day;

    if (!sameDay) {
      fetchDailyPaper();
    }
  }

  Future<void> _loadLikedUrls() async {
    final urls = await _likedStorage.load();
    if (mounted) setState(() => _likedUrls = urls);
  }

  Future<void> _loadSavedUrls() async {
    final urls = await _savedPapersStorage.loadUrls();
    if (mounted) setState(() => _savedUrls = urls);
  }

  Future<void> _loadProfileAndFetch() async {
    final profile = await _profileStorage.load();
    setState(() {
      _profile = profile;
      selectedSubjects = profile?.matchedSubjects;
    });

    final history = await _historyStorage.load();
    final now = DateTime.now();

    // Find the most recent non-disliked paper saved today.
    // This ensures that skipping a paper earlier in the day won't cause
    // the app to force a new fetch on reopen.
    final todayEntry = history.cast<PaperHistoryEntry?>().firstWhere((entry) {
      if (entry == null) return false;
      final viewedAt = entry.viewedAt;
      final isToday =
          viewedAt.year == now.year &&
          viewedAt.month == now.month &&
          viewedAt.day == now.day;
      return isToday && entry.status != PaperFeedbackStatus.disliked;
    }, orElse: () => null);

    if (todayEntry != null) {
      _dislikeCounts = await _feedbackStorage.loadDislikeCounts();
      final subjects = selectedSubjects ?? const [];
      _currentSubject = subjects.isEmpty
          ? null
          : InterestMatcher.subjectForToday(
              subjects,
              dislikeCounts: _dislikeCounts,
            );
      setState(() {
        _paper = todayEntry.paper;
        isLoading = false;
      });
      _markLoadedToday();
      unawaited(_refillBuffer());
      return;
    }

    fetchDailyPaper();
  }

  /// True if the device currently has some form of network connection.
  Future<bool> _hasConnection() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// Builds the set of URLs we should never re-serve: everything already
  /// viewed (history), everything explicitly marked "not for me"
  /// (persisted, so this survives app restarts — not just this session),
  /// plus everything shown earlier this session.
  Future<Set<String>> _excludedUrls() async {
    final history = await _historyStorage.load();
    final dismissed = await _dismissedStorage.load();
    return {
      ..._shownUrlsToday,
      ...dismissed,
      ...history.map((e) => e.paper.url),
    };
  }

  /// Tops up the offline buffer while we have a connection.
  Future<void> _refillBuffer() async {
    try {
      if (await _bufferStorage.count() >= PaperBufferStorage.targetSize) return;

      final excludeUrls = await _excludedUrls();
      final subjects = (selectedSubjects == null || selectedSubjects!.isEmpty)
          ? const ['all']
          : selectedSubjects!;

      for (final subject in subjects) {
        if (await _bufferStorage.count() >= PaperBufferStorage.targetSize) {
          break;
        }
        final candidates = await _service.fetchCandidates(
          subject: subject == 'all' ? null : subject,
          excludeUrls: excludeUrls,
        );
        final ranked = await _recommendationService.rank(
          candidates,
          interests: _profile?.interests ?? const [],
        );
        await _bufferStorage.addIfRoom(ranked, excludeUrls: excludeUrls);
      }
    } catch (_) {
      // Buffer refill is best-effort
    }
  }

  /// Serves the next queued paper as a fallback when a live fetch isn't
  /// possible. Returns true if a buffered paper was shown.
  Future<bool> _tryServeFromBuffer() async {
    final buffered = await _bufferStorage.popNext();
    if (buffered == null) return false;

    await _historyStorage.saveDailyRecommendation(buffered);
    if (!mounted) return true;
    setState(() {
      _paper = buffered;
      _isOffline = true;
      isLoading = false;
    });
    _markLoadedToday();
    return true;
  }

  Future<void> fetchDailyPaper() async {
    if (_isFetchingDaily) return;
    _isFetchingDaily = true;
    setState(() {
      isLoading = true;
      hasError = false;
      _isOffline = false;
    });

    _shownUrlsToday.clear();
    _attempt = 0;
    _subjectRotationIndex = 0;

    try {
      _dislikeCounts = await _feedbackStorage.loadDislikeCounts();
      final subjects = selectedSubjects ?? const [];
      _currentSubject = subjects.isEmpty
          ? null
          : InterestMatcher.subjectForToday(
              subjects,
              dislikeCounts: _dislikeCounts,
            );

      if (!await _hasConnection()) {
        if (await _tryServeFromBuffer()) return;
        throw Exception(
          "You're offline and don't have any saved papers yet. Connect once to build up a queue.",
        );
      }

      final excludeUrls = await _excludedUrls();
      final candidates = await _service.fetchCandidates(
        subject: _currentSubject,
        excludeUrls: excludeUrls,
      );
      final paper = await _recommendationService.choose(
        candidates,
        interests: _profile?.interests ?? const [],
      );
      final selectedPaper =
          paper ??
          await _service.fetchDailyPaper(
            matchedSubjects: selectedSubjects,
            dislikeCounts: _dislikeCounts,
            excludeUrls: excludeUrls,
          );
      await _historyStorage.saveDailyRecommendation(selectedPaper);
      setState(() {
        _paper = selectedPaper;
        isLoading = false;
      });
      _markLoadedToday();
      unawaited(_refillBuffer());
    } on ClockSkewException {
      if (await _tryServeFromBuffer()) return;
      _setErrorState(
        'Date & Time Incorrect',
        'Your device date and time appear to be set incorrectly, which is '
            'blocking secure connections. Please turn on automatic date & '
            'time in your device Settings, then try again.',
      );
    } on Exception catch (e) {
      if (await _tryServeFromBuffer()) return;
      _setErrorState('Connection Error', e.toString());
    } finally {
      _isFetchingDaily = false;
    }
  }

  Future<void> _notForMe() async {
    if (_paper == null || hasError || isLoading) return;
    HapticFeedback.lightImpact();

    final dismissedPaper = _paper!;

    if (_currentSubject != null) {
      await _feedbackStorage.recordNotForMe(_currentSubject!);
      _dislikeCounts[_currentSubject!] =
          (_dislikeCounts[_currentSubject!] ?? 0) + 1;
    }

    await _dismissedStorage.add(dismissedPaper.url);
    await _historyStorage.updateStatus(
      dismissedPaper.url,
      PaperFeedbackStatus.disliked,
    );
    await _recommendationService.recordDismissal(dismissedPaper);

    await _getAnotherPaper();
  }

  Future<void> _getAnotherPaper() async {
    setState(() {
      isLoading = true;
      hasError = false;
    });

    try {
      if (_paper != null) _shownUrlsToday.add(_paper!.url);

      final subjects = selectedSubjects ?? const [];
      String nextSubject;
      if (subjects.length > 1) {
        _subjectRotationIndex = (_subjectRotationIndex + 1) % subjects.length;
        nextSubject = subjects[_subjectRotationIndex];
      } else {
        nextSubject = _currentSubject ?? 'all';
      }

      if (!await _hasConnection()) {
        if (await _tryServeFromBuffer()) return;
        throw Exception(
          "You're offline and don't have any saved papers yet. Connect once to build up a queue.",
        );
      }

      final excludeUrls = await _excludedUrls();
      final candidates = await _service.fetchCandidates(
        subject: nextSubject == 'all' ? null : nextSubject,
        excludeUrls: excludeUrls,
      );
      final newPaper = await _recommendationService.choose(
        candidates,
        interests: _profile?.interests ?? const [],
      );
      final selectedPaper =
          newPaper ??
          await _service.fetchAnotherPaper(
            subject: nextSubject,
            attempt: _attempt++,
            excludeUrls: excludeUrls,
          );

      await _historyStorage.saveDailyRecommendation(selectedPaper);
      setState(() {
        _paper = selectedPaper;
        _currentSubject = nextSubject;
        isLoading = false;
        _isOffline = false;
      });
      _markLoadedToday();
      unawaited(_refillBuffer());
    } on ClockSkewException {
      if (await _tryServeFromBuffer()) return;
      _setErrorState(
        'Date & Time Incorrect',
        'Your device date and time appear to be set incorrectly, which is '
            'blocking secure connections. Please turn on automatic date & '
            'time in your device Settings, then try again.',
      );
    } on Exception catch (e) {
      if (await _tryServeFromBuffer()) return;
      _setErrorState('Connection Error', e.toString());
    } finally {}
  }

  Future<void> _toggleLike() async {
    final paper = _paper;
    if (paper == null || hasError) return;
    HapticFeedback.mediumImpact();

    final liked = !_likedUrls.contains(paper.url);
    setState(() {
      if (liked) {
        _likedUrls.add(paper.url);
      } else {
        _likedUrls.remove(paper.url);
      }
    });
    await _likedStorage.setLiked(paper.url, liked);
    if (liked) {
      await _recommendationService.recordLike(paper);
    } else {
      await _recommendationService.removeLike(paper);
    }
    await _historyStorage.updateStatus(
      paper.url,
      liked ? PaperFeedbackStatus.liked : PaperFeedbackStatus.none,
    );
  }

  Future<void> _toggleSavedPaper() async {
    final paper = _paper;
    if (paper == null || hasError || paper.url.isEmpty) return;
    HapticFeedback.mediumImpact();

    final saved = !_savedUrls.contains(paper.url);
    setState(() {
      if (saved) {
        _savedUrls.add(paper.url);
      } else {
        _savedUrls.remove(paper.url);
      }
    });

    if (saved) {
      await _savedPapersStorage.save(paper);
    } else {
      await _savedPapersStorage.remove(paper.url);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? 'Saved to Library' : 'Removed from Library'),
      ),
    );
  }

  void _setErrorState(String title, String message) {
    setState(() {
      errorTitle = title;
      errorMessage = message;
      isLoading = false;
      hasError = true;
    });
  }

  Future<void> _openPaperLink() async {
    final url = _paper?.url;
    if (url != null && url.isNotEmpty) {
      HapticFeedback.lightImpact();
      final uri = Uri.parse(url);
      final launchUri = uri.hasScheme ? uri : Uri.parse('https://$url');

      final opened = await launchUrl(
        launchUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the publication link')),
        );
      }
    }
  }

  Future<void> _openSettings() async {
    if (_profile == null) return;
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SettingsScreen(profile: _profile!, onSaved: _loadProfileAndFetch),
      ),
    );
  }

  Future<void> _openHistory() async {
    HapticFeedback.lightImpact();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HistoryScreen()));
  }

  Future<void> _openLibrary() async {
    HapticFeedback.lightImpact();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LibraryScreen()));
    await _loadSavedUrls();
  }

  Future<void> _openActionsMenu() async {
    HapticFeedback.lightImpact();
    final palette = AppPalette.of(context);

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 240),
        reverseDuration: Duration(milliseconds: 200),
      ),
      builder: (context) {
        return Padding(
          // Leave room below the floating sheet so its rounded lower edge
          // clears the device gesture area and does not feel clipped.
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
          child: Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _MenuAction(
                    icon: Icons.refresh_rounded,
                    label: 'Reload Recommendation',
                    onTap: () => Navigator.of(context).pop('reload'),
                  ),
                  const SizedBox(height: 8),
                  _MenuAction(
                    icon: Icons.history_rounded,
                    label: 'Reading History',
                    onTap: () => Navigator.of(context).pop('history'),
                  ),
                  const SizedBox(height: 8),
                  _MenuAction(
                    icon: Icons.bookmarks_outlined,
                    label: 'Library',
                    onTap: () => Navigator.of(context).pop('library'),
                  ),
                  const SizedBox(height: 8),
                  _MenuAction(
                    icon: Icons.tune_rounded,
                    label: 'Preferences & Feeds',
                    onTap: () => Navigator.of(context).pop('settings'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    switch (action) {
      case 'reload':
        if (!isLoading) fetchDailyPaper();
        break;
      case 'history':
        await _openHistory();
        break;
      case 'library':
        await _openLibrary();
        break;
      case 'settings':
        await _openSettings();
        break;
    }
  }

  Future<void> _copyCitation() async {
    final paper = _paper;
    if (paper == null || hasError) return;

    await Clipboard.setData(ClipboardData(text: paper.citation()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Citation copied to clipboard')),
    );
  }

  Future<void> _sharePaper() async {
    final paper = _paper;
    if (paper == null || hasError) return;

    final shareText = [
      paper.title,
      if (paper.authors.isNotEmpty) paper.authors,
      if (paper.journal.isNotEmpty)
        paper.publishYear != null
            ? '${paper.journal}, ${paper.publishYear}'
            : paper.journal,
      paper.url,
    ].where((line) => line.isNotEmpty).join('\n');

    final size = MediaQuery.sizeOf(context);
    final origin = Rect.fromLTWH(0, 0, size.width, size.height);

    await Share.share(
      shareText,
      subject: paper.title,
      sharePositionOrigin: origin,
    );
  }

  Future<void> _discussWithChatGPT() async {
    final paper = _paper;
    if (paper == null || hasError) return;
    HapticFeedback.lightImpact();

    const maxAbstractChars = 1200;
    var abstract = paper.abstract;
    if (abstract.length > maxAbstractChars) {
      abstract = '${abstract.substring(0, maxAbstractChars)}...';
    }

    final promptBuffer = StringBuffer()
      ..writeln(
        'Can you explain this paper in plain language and walk me through its key contributions?',
      )
      ..writeln()
      ..writeln('Title: ${paper.title}');
    if (paper.authors.isNotEmpty) {
      promptBuffer.writeln('Authors: ${paper.authors}');
    }
    promptBuffer
      ..writeln('Abstract: $abstract')
      ..write('Link: ${paper.url}');

    final uri = Uri.https('chatgpt.com', '/', {'q': promptBuffer.toString()});

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open ChatGPT')));
    }
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
        leadingWidth: 100, // Matches width reserved on the right
        leading: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: StreakBadge(streakData: _streakData),
          ),
        ),
        title: Text(
          'DAILY THESIS',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 2.5,
            fontSize: 11,
            color: palette.textPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          SizedBox(
            width:
                100, // Matches leadingWidth so title centers exactly on-screen
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.menu_rounded,
                    size: 24,
                    color: palette.textPrimary,
                  ),
                  onPressed: _openActionsMenu,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 620),
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: isLoading
                  ? const SizedBox(
                      key: ValueKey('shimmer'),
                      width: double.infinity,
                      height: 500,
                      child: ShimmerLoader(),
                    )
                  : _buildContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final paper = _paper;
    final palette = AppPalette.of(context);

    return Column(
      key: const ValueKey('content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header (eyebrow, title, context window, byline, divider) ──────
        PaperHeader(
          hasError: hasError,
          errorTitle: errorTitle,
          profile: _profile,
          isOffline: _isOffline,
          paper: paper,
        ),

        // ── Abstract ─────────────────────────────────────────────────────
        Reveal(
          delay: const Duration(milliseconds: 200),
          child: MathText(
            hasError ? errorMessage : (paper?.abstract ?? ''),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              height: 1.65,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),

        // ── Preprint disclaimer ──────────────────────────────────────────
        if (!hasError && paper != null && paper.isPreprint) ...[
          const SizedBox(height: 20),
          Reveal(
            delay: const Duration(milliseconds: 220),
            child: PreprintDisclaimer(sourceName: paper.sourceDisplayName),
          ),
        ],

        const SizedBox(height: 40),

        // ── Primary Action Panel (Ergonomic layout) ────────────────────────
        if (!hasError && paper != null) ...[
          if (paper.url.isNotEmpty)
            Reveal(
              delay: const Duration(milliseconds: 240),
              child: PressButton(
                onPressed: _openPaperLink,
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color: palette.buttonPrimary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Read Full Publication',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: palette.buttonPrimaryText,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: palette.buttonPrimaryText.withValues(alpha: 0.8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),

          // Discovery Feedback Controls (Like / Skip)
          Reveal(
            delay: const Duration(milliseconds: 260),
            child: Row(
              children: [
                Expanded(
                  child: PressButton(
                    onPressed: _toggleSavedPaper,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: _isCurrentSaved
                            ? palette.textPrimary.withValues(alpha: 0.08)
                            : palette.buttonSecondary,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isCurrentSaved
                              ? palette.textPrimary
                              : palette.buttonSecondaryBorder,
                          width: _isCurrentSaved ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isCurrentSaved
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            size: 16,
                            color: _isCurrentSaved
                                ? palette.textPrimary
                                : palette.buttonSecondaryText,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Save',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _isCurrentSaved
                                  ? palette.textPrimary
                                  : palette.buttonSecondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PressButton(
                    onPressed: _toggleLike,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: _isCurrentLiked
                            ? palette.textPrimary.withValues(alpha: 0.08)
                            : palette.buttonSecondary,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isCurrentLiked
                              ? palette.textPrimary
                              : palette.buttonSecondaryBorder,
                          width: _isCurrentLiked ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isCurrentLiked
                                ? Icons.thumb_up_rounded
                                : Icons.thumb_up_outlined,
                            size: 16,
                            color: _isCurrentLiked
                                ? palette.textPrimary
                                : palette.buttonSecondaryText,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Like',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _isCurrentLiked
                                  ? palette.textPrimary
                                  : palette.buttonSecondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PressButton(
                    onPressed: _notForMe,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: palette.buttonSecondary,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: palette.buttonSecondaryBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.thumb_down_outlined,
                            size: 16,
                            color: palette.buttonSecondaryText,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Skip',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: palette.buttonSecondaryText,
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

          // Document Secondary Action Row (Cite, Share, Discuss)
          const SizedBox(height: 12),
          Reveal(
            delay: const Duration(milliseconds: 280),
            child: Row(
              children: [
                _buildUtilityButton(
                  icon: Icons.format_quote_rounded,
                  label: 'Cite',
                  onPressed: _copyCitation,
                  palette: palette,
                ),
                const SizedBox(width: 8),
                _buildUtilityButton(
                  icon: Icons.ios_share_rounded,
                  label: 'Share',
                  onPressed: _sharePaper,
                  palette: palette,
                ),
                const SizedBox(width: 8),
                _buildUtilityButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Discuss',
                  onPressed: _discussWithChatGPT,
                  palette: palette,
                ),
              ],
            ),
          ),
        ],

        // ── Error retry ───────────────────────────────────────────────────
        if (hasError)
          Reveal(
            delay: const Duration(milliseconds: 100),
            child: PressButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                fetchDailyPaper();
              },
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  border: Border.all(color: palette.textPrimary, width: 1.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'Try Again',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildUtilityButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required AppPalette palette,
  }) {
    return Expanded(
      child: PressButton(
        onPressed: onPressed,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: palette.buttonSecondary,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: palette.buttonSecondaryBorder.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: palette.buttonSecondaryText),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: palette.buttonSecondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.buttonSecondary,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: palette.buttonSecondaryText),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: palette.buttonSecondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
