import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../api/client.dart';
import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/image_source_sheet.dart';
import '../widgets/plant_image.dart';
import '../widgets/primary_button.dart';

/// Growth Journey — a plant's growth timeline as a winding vine, one dated
/// photo "memory" per node. Green Thumb-and-up feature (see plans.dart);
/// works for wishlist plants too, same as diagnose/photo-upload elsewhere.
/// Deliberately simple (v1): no in-place editing, just add/view/delete.
class GrowthJourneyScreen extends StatefulWidget {
  const GrowthJourneyScreen({super.key});
  @override
  State<GrowthJourneyScreen> createState() => _GrowthJourneyScreenState();
}

class _GrowthJourneyScreenState extends State<GrowthJourneyScreen> {
  String _status = 'loading'; // loading | idle | error
  String _errorMessage = '';
  List<GrowthMemory> _memories = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    final plant = appState.growthJourneyPlant;
    if (plant == null) {
      setState(() => _status = 'idle');
      return;
    }
    try {
      final memories = await appState.api.listGrowthMemories(appState.token!, plant.id);
      if (!mounted) return;
      setState(() {
        _memories = memories;
        _status = 'idle';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'error';
        _errorMessage = 'Could not load this plant\'s growth journey.';
      });
    }
  }

  Future<void> _handleAdd() async {
    final appState = context.read<AppState>();
    final plant = appState.growthJourneyPlant;
    if (plant == null) return;

    final source = await showImageSourceSheet(context);
    if (source == null) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1024);
    if (file == null) return;
    if (!mounted) return;

    final input = await showModalBottomSheet<_NewMemoryInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMemorySheet(imageFile: File(file.path)),
    );
    if (input == null) return;

    try {
      final bytes = await File(file.path).readAsBytes();
      final imageBase64 = base64Encode(bytes);
      final memory = await appState.api.createGrowthMemory(
        appState.token!,
        plant.id,
        name: input.name,
        note: input.note,
        imageBase64: imageBase64,
      );
      if (!mounted) return;
      setState(() => _memories = [..._memories, memory]);
      appState.trackEvent('growth_memory_added');
      unawaited(appState.refreshEntitlement());
    } on ApiException catch (err) {
      if (err.errorCode == 'PLAN_LIMIT_EXCEEDED') {
        appState.trackEvent('growth_memory_limit_reached');
        appState.goTo('paywall', withReturnTo: 'growthJourney');
      } else if (err.errorCode == 'GUEST_SIGNIN_REQUIRED') {
        appState.trackEvent('growth_memory_limit_reached');
        appState.guestGateReason = err.message;
        appState.goTo('guestGate', withReturnTo: 'growthJourney');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save this memory. Try again.')));
      }
    }
  }

  Future<void> _handleDelete(GrowthMemory memory) async {
    final appState = context.read<AppState>();
    final plant = appState.growthJourneyPlant;
    if (plant == null) return;
    setState(() => _memories = _memories.where((m) => m.id != memory.id).toList());
    try {
      await appState.api.deleteGrowthMemory(appState.token!, plant.id, memory.id);
      unawaited(appState.refreshEntitlement());
    } catch (e) {
      debugPrint('Failed to delete growth memory: $e');
      unawaited(_load()); // reconcile with server truth if the delete failed
    }
  }

  /// Fade-in/scale-in on open, and — since showGeneralDialog runs this same
  /// transition in reverse on pop — the same fade/scale out on close.
  Future<void> _openDetail(GrowthMemory memory) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: memory.name,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, anim, secondaryAnim) => Center(
        child: _MemoryDetailCard(
          memory: memory,
          onDelete: () {
            Navigator.of(context).pop();
            _handleDelete(memory);
          },
        ),
      ),
      transitionBuilder: (context, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curved), child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final plant = appState.growthJourneyPlant;
    final growth = appState.entitlement?.growthMemories;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => appState.goBack(fallback: 'home')),
        title: const Text('Growth Journey'),
        actions: [
          IconButton(
            tooltip: 'Add a memory',
            onPressed: plant == null ? null : _handleAdd,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      body: plant == null
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text('This plant is no longer available.', style: Theme.of(context).textTheme.bodyMedium)),
            )
          : _status == 'loading'
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _status == 'error'
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text(_errorMessage, style: Theme.of(context).textTheme.bodyMedium)),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${plant.nickname} · ${plant.species ?? "Not identified"}',
                                  style: AppTypography.body(AppColors.textSecondaryOf(context)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (growth != null && !growth.isUnlimited)
                                Text(
                                  '${growth.count}/${growth.limit == 0 ? "0" : growth.limit}',
                                  style: AppTypography.caption(AppColors.textSecondaryOf(context)),
                                ),
                            ],
                          ),
                        ),
                        Expanded(child: _VineView(memories: _memories, onTapNode: _openDetail)),
                      ],
                    ),
    );
  }
}

/// The winding vine itself — root at the bottom, oldest memory nearest the
/// root, newest at the top (the plant's own growth reads bottom-to-top).
class _VineView extends StatelessWidget {
  final List<GrowthMemory> memories;
  final ValueChanged<GrowthMemory> onTapNode;
  const _VineView({required this.memories, required this.onTapNode});

  static const double _nodeSpacing = 175;
  static const double _sideOffset = 58;
  static const double _rootHeight = 130;
  static const double _tipHeight = 90;
  static const double _nodeSize = 72;
  static const double _potWidth = 120;
  static const double _potHeight = 96;
  // How far down from the top of the pot's box the stem should actually
  // terminate — the generated pot image (see the prompt this was built
  // from) has generous padding around the pot itself, so the visual rim/
  // soil line sits a bit below the box's very top edge, not at y=0.
  static const double _potTopInset = 22;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final center = width / 2;
      final totalHeight = _rootHeight + _tipHeight + memories.length * _nodeSpacing + (memories.isEmpty ? 60 : 0);

      // Anchor points bottom-to-top: root -> oldest memory -> ... -> newest -> tip.
      // The root anchor sits near the TOP of the pot's box (where soil/rim
      // is), not its vertical center — so the stem visually plugs into the
      // pot instead of running through its middle (see _potHeight below).
      final anchors = <Offset>[Offset(center, totalHeight - _rootHeight + _potTopInset)];
      for (int i = 0; i < memories.length; i++) {
        final x = center + (i.isEven ? -_sideOffset : _sideOffset);
        final y = totalHeight - _rootHeight - i * _nodeSpacing - _nodeSpacing / 2;
        anchors.add(Offset(x, y));
      }
      anchors.add(Offset(center, _tipHeight / 2));

      return SingleChildScrollView(
        reverse: true, // land on the newest (top) memory first
        child: SizedBox(
          width: width,
          height: totalHeight,
          child: Stack(
            children: [
              // Background texture — tiles vertically so it stays
              // continuous no matter how tall the timeline grows. Falls
              // back to nothing (plain scaffold background) until
              // assets/images/growth_vine_background.png actually exists.
              Positioned.fill(
                child: Image.asset(
                  'assets/images/growth_vine_background.png',
                  repeat: ImageRepeat.repeatY,
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topCenter,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              ),
              CustomPaint(
                size: Size(width, totalHeight),
                painter: _VinePainter(
                  anchors: anchors,
                  stemStart: AppColors.sage,
                  stemEnd: AppColors.primaryTintPairOf(context).$2,
                  leafColor: AppColors.sage,
                ),
              ),
              // Root / pot — painted after (so it visually sits in front
              // of) the stem, which is what makes the vine look like it's
              // growing out of it rather than passing behind/through it.
              Positioned(
                left: center - _potWidth / 2,
                top: totalHeight - _rootHeight,
                child: SizedBox(
                  width: _potWidth,
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/images/growth_pot.png',
                        width: _potWidth,
                        height: _potHeight,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: _potWidth * 0.8,
                          height: _potHeight * 0.55,
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('PLANTED', style: AppTypography.caption(AppColors.textSecondaryOf(context))),
                    ],
                  ),
                ),
              ),
              // Growing tip
              Positioned(
                left: center - 14,
                top: 12,
                child: Icon(Icons.eco, color: AppColors.sage, size: 28),
              ),
              // Empty state
              if (memories.isEmpty)
                Positioned(
                  left: 24,
                  right: 24,
                  top: totalHeight / 2 - 40,
                  child: Center(
                    child: Text(
                      'No memories yet — tap + to add the first one.',
                      textAlign: TextAlign.center,
                      style: AppTypography.body(AppColors.textSecondaryOf(context)),
                    ),
                  ),
                ),
              // Nodes
              for (int i = 0; i < memories.length; i++)
                Positioned(
                  left: anchors[i + 1].dx - _nodeSize / 2,
                  top: anchors[i + 1].dy - _nodeSize / 2,
                  width: _nodeSize + 20,
                  child: GestureDetector(
                    onTap: () => onTapNode(memories[i]),
                    onLongPress: () => onTapNode(memories[i]),
                    child: Column(
                      children: [
                        Container(
                          width: _nodeSize,
                          height: _nodeSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.sage, width: 2.5),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 4))],
                          ),
                          child: ClipOval(child: PlantImage(url: memories[i].photoUrl, borderRadius: 999)),
                        ),
                        const SizedBox(height: 6),
                        // Small backdrop, not bare text — the stem's curve
                        // sometimes passes directly behind a date label
                        // (see the two side-offset node positions above),
                        // which read as illegible without this.
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.bgOf(context).withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            _formatDate(memories[i].createdAt),
                            style: AppTypography.caption(AppColors.textSecondaryOf(context)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  String _formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';
}

class _VinePainter extends CustomPainter {
  final List<Offset> anchors;
  final Color stemStart;
  final Color stemEnd;
  final Color leafColor;

  _VinePainter({required this.anchors, required this.stemStart, required this.stemEnd, required this.leafColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (anchors.length < 2) return;
    final rect = Rect.fromPoints(anchors.first, anchors.last);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(colors: [stemStart, stemEnd], begin: Alignment.bottomCenter, end: Alignment.topCenter).createShader(rect);

    final path = Path()..moveTo(anchors.first.dx, anchors.first.dy);
    final leafPaint = Paint()..color = leafColor.withValues(alpha: 0.85);
    for (int i = 1; i < anchors.length; i++) {
      final p0 = anchors[i - 1];
      final p1 = anchors[i];
      final dy = (p0.dy - p1.dy) / 2;
      path.cubicTo(p0.dx, p0.dy - dy, p1.dx, p1.dy + dy, p1.dx, p1.dy);

      // small leaf accent at the segment midpoint
      final mid = Offset.lerp(p0, p1, 0.5)!;
      canvas.save();
      canvas.translate(mid.dx, mid.dy);
      canvas.rotate(i.isEven ? -0.5 : 0.5);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 22, height: 12), leafPaint);
      canvas.restore();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _VinePainter oldDelegate) => oldDelegate.anchors != anchors;
}

class _MemoryDetailCard extends StatelessWidget {
  final GrowthMemory memory;
  final VoidCallback onDelete;
  const _MemoryDetailCard({required this.memory, required this.onDelete});

  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 40, offset: const Offset(0, 20))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  AspectRatio(aspectRatio: 1.25, child: PlantImage(url: memory.photoUrl, borderRadius: 0)),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 15, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memory.name,
                      style: GoogleFonts.unifrakturMaguntia(fontSize: 28, color: AppColors.primaryTintPairOf(context).$2, height: 1.2),
                    ),
                    const SizedBox(height: 4),
                    Text(_formatDate(memory.createdAt), style: AppTypography.eyebrow(AppColors.sage)),
                    if (memory.note != null && memory.note!.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppColors.bgOf(context), borderRadius: BorderRadius.circular(AppRadius.md)),
                        child: Text(
                          '“${memory.note}”',
                          style: AppTypography.body(AppColors.textOf(context)).copyWith(fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: onDelete,
                        child: Text('Delete this memory', style: AppTypography.bodyStrong(AppColors.accent)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

class _NewMemoryInput {
  final String name;
  final String? note;
  _NewMemoryInput({required this.name, this.note});
}

class _AddMemorySheet extends StatefulWidget {
  final File imageFile;
  const _AddMemorySheet({required this.imageFile});
  @override
  State<_AddMemorySheet> createState() => _AddMemorySheetState();
}

class _AddMemorySheetState extends State<_AddMemorySheet> {
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(color: AppColors.borderOf(context), borderRadius: BorderRadius.circular(999)),
              ),
            ),
            Text('New growth memory', style: AppTypography.h2(AppColors.textOf(context))),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Image.file(widget.imageFile, height: 150, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: 18),
            Text('NAME THIS MEMORY', style: AppTypography.eyebrow(AppColors.sage)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              autofocus: true,
              maxLength: 100,
              decoration: const InputDecoration(hintText: 'e.g. First new leaf'),
            ),
            const SizedBox(height: 8),
            Text('NOTE · OPTIONAL', style: AppTypography.eyebrow(AppColors.sage)),
            const SizedBox(height: 6),
            TextField(
              controller: _noteController,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Say anything worth remembering about this moment…'),
            ),
            const SizedBox(height: 8),
            PrimaryButton(
              label: 'Save memory',
              onPressed: _nameController.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                        _NewMemoryInput(
                          name: _nameController.text.trim(),
                          note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
