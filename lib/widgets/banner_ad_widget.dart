import 'package:flutter/material.dart';

/// Placeholder retained while AdMob is disabled.
///
/// The project deliberately does not include `google_mobile_ads`, so this
/// widget must not reference its native types. Keeping the public widget lets
/// a future AdMob implementation be added without changing screen layouts.
class BannerAdWidget extends StatelessWidget {
  const BannerAdWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
