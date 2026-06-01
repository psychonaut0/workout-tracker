import 'package:flutter/material.dart';

enum OnboardingChoice { empty, starter }

/// First-launch screen: lets the user start with an empty library or seed a
/// starter set of exercises (+ default muscle targets). Everything seeded is
/// editable/deletable later. [onChosen] performs the seeding + marks onboarding
/// complete; this widget only collects the choice.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onChosen});

  final Future<void> Function(OnboardingChoice choice) onChosen;

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
                onPressed: () => onChosen(OnboardingChoice.starter),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Add starter exercises'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => onChosen(OnboardingChoice.empty),
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
