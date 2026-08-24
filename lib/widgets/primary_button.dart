import 'package:flutter/material.dart';

/// Dark-forest-green filled button — the app's one primary action style
/// ("Scan Plant", "Add to My Plants", "Continue"). Wraps ElevatedButton
/// (theme already styles it — see AppTheme.light/dark) purely to give call
/// sites one obvious, reusable name instead of inline ElevatedButton.styleFrom
/// overrides drifting apart screen to screen.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2, valueColor: AlwaysStoppedAnimation(Colors.white)),
          )
        : icon != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
              )
            : Text(label);

    final button = ElevatedButton(onPressed: loading ? null : onPressed, child: child);
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Cream/sage outlined button — secondary actions alongside a PrimaryButton.
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  const SecondaryButton({super.key, required this.label, required this.onPressed, this.icon, this.expand = true});

  @override
  Widget build(BuildContext context) {
    final child = icon != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Icon(icon, size: 17), const SizedBox(width: 8), Text(label)],
          )
        : Text(label);

    final button = OutlinedButton(onPressed: onPressed, child: child);
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
