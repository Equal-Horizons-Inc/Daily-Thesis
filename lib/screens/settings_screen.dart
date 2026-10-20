import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user_profile.dart';
import '../services/interest_matcher.dart';
import '../services/notification_service.dart';
import '../services/profile_storage.dart';
import '../services/text_scale_storage.dart';
import '../services/theme_mode_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/interest_picker.dart';
import '../widgets/press_button.dart';

class SettingsScreen extends StatefulWidget {
  final UserProfile profile;
  final VoidCallback onSaved;

  const SettingsScreen({
    super.key,
    required this.profile,
    required this.onSaved,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _nameController;
  late Set<String> _selectedInterests;
  late ThemeMode _themeMode;
  late AppTextScale _textScale;
  bool _reminderEnabled = false;
  bool _reminderLoaded = false;
  bool _updatingReminder = false;
  bool _isSaving = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 9, minute: 0);
  final _storage = ProfileStorage();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _selectedInterests = widget.profile.interests.toSet();
    _themeMode = ThemeModeController.instance.notifier.value;
    _textScale = TextScaleController.instance.notifier.value;
    _loadReminderSettings();
  }

  Future<void> _loadReminderSettings() async {
    final settings = await NotificationService.instance.loadSettings();
    if (!mounted) return;
    setState(() {
      _reminderEnabled = settings.enabled;
      _reminderTime = TimeOfDay(hour: settings.hour, minute: settings.minute);
      _reminderLoaded = true;
    });
  }

  Future<void> _setReminderEnabled(bool enabled) async {
    setState(() => _updatingReminder = true);
    var success = false;
    try {
      success = await NotificationService.instance.setEnabled(enabled);
    } catch (_) {
      success = false;
    }
    if (!mounted) return;
    setState(() {
      _updatingReminder = false;
      if (success) _reminderEnabled = enabled;
    });
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not enable the reminder. Check notification settings and try again.',
          ),
        ),
      );
    } else if (enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Daily reminder set for ${_reminderTime.format(context)}.',
          ),
        ),
      );
    }
  }

  Future<void> _chooseReminderTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
    );
    if (time == null) return;
    try {
      await NotificationService.instance.setTime(time.hour, time.minute);
      if (mounted) setState(() => _reminderTime = time);
      if (mounted && _reminderEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Daily reminder updated to ${time.format(context)}.'),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update the reminder time.')),
      );
    }
  }

  Future<void> _sendTestReminder() async {
    try {
      await NotificationService.instance.sendTestNotification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Test scheduled. Leave the app; it should arrive in 10 seconds.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send a test notification.')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _toggleInterest(String label) {
    setState(() {
      if (_selectedInterests.contains(label)) {
        _selectedInterests.remove(label);
      } else {
        _selectedInterests.add(label);
      }
    });
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    setState(() => _themeMode = mode);
    await ThemeModeController.instance.setMode(mode);
  }

  Future<void> _setTextScale(AppTextScale scale) async {
    if (_textScale == scale) return;
    setState(() => _textScale = scale);
    await TextScaleController.instance.setScale(scale);
  }

  Future<void> _save() async {
    if (_selectedInterests.isEmpty || _isSaving) return;

    setState(() => _isSaving = true);
    final interests = _selectedInterests.toList();
    final matchedSubjects = InterestMatcher.subjectsForSelections(interests);

    final updated = UserProfile(
      name: _nameController.text.trim(),
      interests: interests,
      matchedSubjects: matchedSubjects,
    );

    try {
      await _storage.save(updated);
      HapticFeedback.mediumImpact();
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save your preferences.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final canSave = _selectedInterests.isNotEmpty;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'SETTINGS',
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
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  const SizedBox(height: 8),
                  _SettingsSection(
                    title: 'Your profile',
                    subtitle: 'How we address you in the app',
                    palette: palette,
                    child: TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      style: TextStyle(
                        fontSize: 16,
                        color: palette.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Your name',
                        filled: true,
                        fillColor: palette.background,
                        prefixIcon: Icon(
                          Icons.person_outline_rounded,
                          color: palette.textTertiary,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: palette.borderSoft),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: palette.borderSoft),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: palette.textSecondary),
                        ),
                      ),
                    ),
                  ),
                  _SettingsSection(
                    title: 'Appearance',
                    subtitle: 'Choose a look and comfortable reading size',
                    palette: palette,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SettingLabel('THEME', palette: palette),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _ThemeChoice(
                              label: 'System',
                              selected: _themeMode == ThemeMode.system,
                              onTap: () => _setThemeMode(ThemeMode.system),
                            ),
                            _ThemeChoice(
                              label: 'Light',
                              selected: _themeMode == ThemeMode.light,
                              onTap: () => _setThemeMode(ThemeMode.light),
                            ),
                            _ThemeChoice(
                              label: 'Dark',
                              selected: _themeMode == ThemeMode.dark,
                              onTap: () => _setThemeMode(ThemeMode.dark),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _SettingLabel('TEXT SIZE', palette: palette),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final scale in AppTextScale.values)
                              _ThemeChoice(
                                label: scale.label,
                                selected: _textScale == scale,
                                onTap: () => _setTextScale(scale),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _SettingsSection(
                    title: 'Daily reminder',
                    subtitle: 'A private reminder scheduled on this device',
                    palette: palette,
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Remind me each day',
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Get a nudge to read today’s paper',
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          value: _reminderEnabled,
                          onChanged: _reminderLoaded && !_updatingReminder
                              ? _setReminderEnabled
                              : null,
                        ),
                        AnimatedOpacity(
                          opacity: _reminderEnabled ? 1 : 0.55,
                          duration: const Duration(milliseconds: 160),
                          child: Material(
                            color: palette.background,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: _reminderLoaded
                                  ? _chooseReminderTime
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      size: 19,
                                      color: palette.textSecondary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Reminder time',
                                        style: TextStyle(
                                          color: palette.textPrimary,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _reminderTime.format(context),
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 20,
                                      color: palette.textTertiary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed:
                                _reminderLoaded &&
                                    _reminderEnabled &&
                                    !_updatingReminder
                                ? _sendTestReminder
                                : null,
                            icon: const Icon(
                              Icons.notifications_active_outlined,
                            ),
                            label: const Text('Schedule test notification'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _SettingsSection(
                    title: 'Research interests',
                    subtitle: 'Used to personalize your recommendations',
                    palette: palette,
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: palette.background,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_selectedInterests.length} selected',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    child: InterestPicker(
                      selectedLabels: _selectedInterests,
                      onToggle: _toggleInterest,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              decoration: BoxDecoration(
                color: palette.background,
                border: Border(top: BorderSide(color: palette.borderSoft)),
              ),
              child: PressButton(
                onPressed: canSave && !_isSaving ? _save : () {},
                child: Container(
                  width: double.infinity,
                  height: 54,
                  decoration: BoxDecoration(
                    color: canSave
                        ? palette.buttonPrimary
                        : palette.buttonPrimary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: _isSaving
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.buttonPrimaryText,
                            ),
                          )
                        : Text(
                            'Save changes',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: palette.buttonPrimaryText,
                            ),
                          ),
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

class _SettingsSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final AppPalette palette;
  final Widget child;
  final Widget? trailing;

  const _SettingsSection({
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: palette.borderSoft),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingLabel extends StatelessWidget {
  final String text;
  final AppPalette palette;

  const _SettingLabel(this.text, {required this.palette});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: palette.textTertiary,
      letterSpacing: 1.2,
    ),
  );
}

class _ThemeChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? palette.chipSelectedBackground
              : palette.chipUnselectedBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? palette.chipSelectedBorder
                : palette.chipUnselectedBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected
                ? palette.chipSelectedText
                : palette.chipUnselectedText,
          ),
        ),
      ),
    );
  }
}
