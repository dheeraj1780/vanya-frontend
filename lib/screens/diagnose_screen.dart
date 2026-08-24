import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../api/client.dart';
import '../theme/app_theme.dart';
import '../widgets/image_source_sheet.dart';
import '../widgets/primary_button.dart';

class DiagnoseScreen extends StatefulWidget {
  const DiagnoseScreen({super.key});
  @override
  State<DiagnoseScreen> createState() => _DiagnoseScreenState();
}

class _DiagnoseScreenState extends State<DiagnoseScreen> {
  String _status = 'idle'; // idle | need-closeup | diagnosing | error
  String _errorMessage = '';
  String? _fullPlantBase64;
  File? _fullPlantFile; // kept only for the on-screen preview, not sent anywhere new

  Future<void> _handleCapture() async {
    final appState = context.read<AppState>();
    // Tier-aware proactive check (real enforcement is always server-side,
    // via check_diagnose_limit) — falls back to blocking outright if
    // entitlement hasn't loaded yet, same conservative default as
    // AddPlantScreen's plant-limit pre-check.
    final diagnose = appState.entitlement?.diagnose;
    if (diagnose == null || diagnose.atLimit) {
      appState.trackEvent('diagnose_limit_reached');
      if (appState.isGuest) {
        appState.guestGateReason = "You've used your free diagnosis as a guest. Sign in to become a Plantie and keep growing your garden.";
        appState.goTo('guestGate', withReturnTo: appState.returnTo);
      } else {
        appState.goTo('paywall', withReturnTo: appState.returnTo);
      }
      return;
    }

    final source = await showImageSourceSheet(context);
    if (source == null) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1024);
    if (file == null) return;
    final bytes = await File(file.path).readAsBytes();
    final imageBase64 = base64Encode(bytes);

    if (_fullPlantBase64 == null) {
      setState(() {
        _fullPlantBase64 = imageBase64;
        _fullPlantFile = File(file.path);
        _status = 'need-closeup';
      });
      return;
    }

    setState(() {
      _status = 'diagnosing';
      _errorMessage = '';
    });

    try {
      final result = await appState.api.diagnosePlant(
        appState.token!,
        appState.selectedPlantId!,
        _fullPlantBase64!,
        imageBase64,
      );
      setState(() {
        _status = 'idle';
        _fullPlantBase64 = null;
        _fullPlantFile = null;
      });
      appState.trackEvent(appState.isGuest ? 'guest_diagnose_used' : 'plantie_diagnose_used');
      appState.handleDiagnosisResult(result);
    } on ApiException catch (err) {
      setState(() {
        _status = 'error';
        _fullPlantBase64 = null;
        _fullPlantFile = null;
      });
      if (err.errorCode == 'PLAN_LIMIT_EXCEEDED') {
        appState.trackEvent('diagnose_limit_reached');
        appState.goTo('paywall', withReturnTo: appState.returnTo);
      } else if (err.errorCode == 'GUEST_SIGNIN_REQUIRED') {
        appState.trackEvent('diagnose_limit_reached');
        appState.guestGateReason = err.message;
        appState.goTo('guestGate', withReturnTo: appState.returnTo);
      } else {
        setState(() => _errorMessage = err.message);
      }
    } catch (e) {
      setState(() {
        _status = 'error';
        _fullPlantBase64 = null;
        _fullPlantFile = null;
        _errorMessage = 'Could not diagnose this plant. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _status == 'diagnosing'
        ? 'Diagnosing…'
        : _status == 'need-closeup'
            ? 'Full plant captured — now a close-up of the problem'
            : 'Tap to add a photo';
    final buttonLabel = _status == 'diagnosing'
        ? 'Diagnosing…'
        : _status == 'need-closeup'
            ? 'Add close-up photo'
            : 'Add photos';

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () {
          final appState = context.read<AppState>();
          appState.goBack(fallback: appState.returnTo);
        }),
        title: const Text('Diagnose'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Take or choose a photo of the whole plant, then a close-up of the problem area.', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: AppColors.primaryTintPairOf(context).$1, borderRadius: BorderRadius.circular(20)),
                child: _fullPlantFile != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(_fullPlantFile!, fit: BoxFit.cover),
                          if (_status != 'diagnosing')
                            Positioned(
                              left: 10,
                              top: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                                child: const Text('Full plant ✓', style: TextStyle(color: Colors.white, fontSize: 11)),
                              ),
                            ),
                          if (_status == 'diagnosing')
                            Container(
                              color: Colors.black45,
                              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                            ),
                        ],
                      )
                    // Same fix as BUG-D001 on the Scan Plant screen: this
                    // icon+label looked like a button but had no onTap —
                    // only the separate "Add photos" button below it
                    // actually worked. Now it does the same thing.
                    : InkWell(
                        onTap: _status == 'diagnosing' ? null : _handleCapture,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.camera_alt_outlined, size: 34, color: AppColors.primaryTintPairOf(context).$2),
                              const SizedBox(height: 10),
                              Text(label, style: Theme.of(context).textTheme.bodyMedium),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
            if (_errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(_errorMessage, style: const TextStyle(color: AppColors.accent, fontSize: 12.5)),
              ),
            const SizedBox(height: 10),
            PrimaryButton(
              label: buttonLabel,
              loading: _status == 'diagnosing',
              onPressed: _status == 'diagnosing' ? null : _handleCapture,
            ),
          ],
        ),
      ),
    );
  }
}
