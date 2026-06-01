import 'package:flutter/material.dart';

enum OnboardingChoice { empty, starter }

/// First-launch screen: lets the user start with an empty library or seed a
/// starter set of exercises (+ default muscle targets). Everything seeded is
/// editable/deletable later. [onChosen] performs the seeding + marks onboarding
/// complete; this widget only collects the choice.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onChosen});

  final Future<void> Function(OnboardingChoice choice) onChosen;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _busy = false;

  Future<void> _choose(OnboardingChoice choice) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onChosen(choice);
    } finally {
      // On success the shell replaces this widget; the mounted guard makes a
      // failed seed re-enable the buttons so the user can retry.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Welcome', style: t.headlineMedium),
              const SizedBox(height: 12),
              Text(
                'How would you like to start? You can change everything later.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed:
                    _busy ? null : () => _choose(OnboardingChoice.starter),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Add starter exercises'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : () => _choose(OnboardingChoice.empty),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Start empty'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
