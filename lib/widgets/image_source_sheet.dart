import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';

/// Camera vs gallery picker — shared by AddPlantScreen and DiagnoseScreen,
/// which both used to hardcode ImageSource.camera with no way to pick an
/// existing photo.
Future<ImageSource?> showImageSourceSheet(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Material(
      // Material (not a plain Container+BoxDecoration) so ListTile's ink
      // splashes and background actually paint — they render on the
      // nearest Material ancestor, which an intermediate DecoratedBox with
      // its own background would otherwise visually hide.
      color: AppColors.surfaceOf(context),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
                title: const Text('Take photo'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Shared by AddPlantScreen and DiagnoseScreen's own _handleCapture —
/// combines showImageSourceSheet with the actual pickImage call.
///
/// BUG this fixed: neither screen ever checked/requested CAMERA permission
/// before calling picker.pickImage(source: ImageSource.camera) — found
/// live testing the "only this time" onboarding grant expiring (as Android
/// always eventually revokes it, force-close or not). Once camera access
/// isn't granted, pickImage's camera path just silently returns null —
/// no OS permission prompt, no error, nothing — so tapping "Take photo"
/// looked like a completely dead button, with no way for a normal user to
/// figure out why. Gallery deliberately isn't gated the same way: modern
/// Android's photo picker (what image_picker uses under the hood) doesn't
/// need a runtime permission at all.
Future<XFile?> pickPlantImage(BuildContext context) async {
  final source = await showImageSourceSheet(context);
  if (source == null) return null;

  if (source == ImageSource.camera) {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (!status.isGranted) {
      if (!context.mounted) return null;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Camera access needed'),
          content: Text(
            status.isPermanentlyDenied
                ? "VANYA needs camera access to scan a plant. It's currently turned off — enable it in your device's app settings to continue."
                : 'VANYA needs camera access to scan a plant. Please allow it and try again.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            if (status.isPermanentlyDenied)
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  openAppSettings();
                },
                child: const Text('Open settings', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      );
      return null;
    }
  }

  final picker = ImagePicker();
  return picker.pickImage(source: source, imageQuality: 80, maxWidth: 1024);
}
