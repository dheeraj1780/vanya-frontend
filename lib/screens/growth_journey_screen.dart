import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api/client.dart';
import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/image_source_sheet.dart';
import '../widgets/plant_image.dart';
import '../widgets/primary_button.dart';

/// Bundled Growth Journey background options — key must match one of
/// plant_service._GROWTH_BACKGROUND_PRESETS on the backend exactly.
/// assetPath/potAssetPath point at files this repo doesn't have yet; until
/// they're added (see BackgroundPickerSheet's swatch fallback and
/// _VineView's pot errorBuilder), the picker shows a plain color swatch
/// and the vine screen falls back to the generic pot/no texture.
///
/// potAssetPath is a themed pot matching this background's mood (e.g. an
/// ornate urn for Gothic, a woven basket for Rainforest) — picking a
/// background picks its pot too, rather than mixing a random pot under a
/// themed background. The plain "assets/images/growth_pot.png" (see
/// _VineView) is only the fallback for no-background-chosen/custom-photo.
class GrowthBackgroundPreset {
  final String key;
  final String label;
  final String assetPath;
  final String potAssetPath;
  final Color swatchColor;
  const GrowthBackgroundPreset({
    required this.key,
    required this.label,
    required this.assetPath,
    required this.potAssetPath,
    required this.swatchColor,
  });
}

const List<GrowthBackgroundPreset> kGrowthBackgroundPresets = [
  GrowthBackgroundPreset(key: 'pressed_journal', label: 'Pressed Journal', assetPath: 'assets/images/growth_bg_pressed_journal.jpg', potAssetPath: 'assets/images/growth_pot_pressed_journal.png', swatchColor: Color(0xFFE9E2D2)),
  GrowthBackgroundPreset(key: 'golden_hour', label: 'Golden Hour', assetPath: 'assets/images/growth_bg_golden_hour.jpg', potAssetPath: 'assets/images/growth_pot_golden_hour.png', swatchColor: Color(0xFFF3E3D3)),
  GrowthBackgroundPreset(key: 'greenhouse', label: 'Greenhouse', assetPath: 'assets/images/growth_bg_greenhouse.jpg', potAssetPath: 'assets/images/growth_pot_greenhouse.png', swatchColor: Color(0xFFE7EEE6)),
  GrowthBackgroundPreset(key: 'nature_diary', label: 'Nature Diary', assetPath: 'assets/images/growth_bg_nature_diary.jpg', potAssetPath: 'assets/images/growth_pot_nature_diary.png', swatchColor: Color(0xFFDCEBE0)),
  GrowthBackgroundPreset(key: 'forest_dusk', label: 'Forest Dusk', assetPath: 'assets/images/growth_bg_forest_dusk.jpg', potAssetPath: 'assets/images/growth_pot_forest_dusk.png', swatchColor: Color(0xFF1C231C)),
  GrowthBackgroundPreset(key: 'gothic', label: 'Gothic Botanical', assetPath: 'assets/images/growth_bg_gothic.jpg', potAssetPath: 'assets/images/growth_pot_gothic.png', swatchColor: Color(0xFF12160F)),
  GrowthBackgroundPreset(key: 'desi_heritage', label: 'Desi Heritage', assetPath: 'assets/images/growth_bg_desi_heritage.jpg', potAssetPath: 'assets/images/growth_pot_desi_heritage.png', swatchColor: Color(0xFFEFC9A0)),
  GrowthBackgroundPreset(key: 'rainforest', label: 'Rainforest', assetPath: 'assets/images/growth_bg_rainforest.jpg', potAssetPath: 'assets/images/growth_pot_rainforest.png', swatchColor: Color(0xFF1F3D30)),
  GrowthBackgroundPreset(key: 'ink_wash', label: 'Ink Wash Garden', assetPath: 'assets/images/growth_bg_ink_wash.jpg', potAssetPath: 'assets/images/growth_pot_ink_wash.png', swatchColor: Color(0xFFF0EDE4)),
  GrowthBackgroundPreset(key: 'heirloom_tapestry', label: 'Heirloom Tapestry', assetPath: 'assets/images/growth_bg_heirloom_tapestry.jpg', potAssetPath: 'assets/images/growth_pot_heirloom_tapestry.png', swatchColor: Color(0xFFD9C2A0)),
];

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
  final GlobalKey _shareCardKey = GlobalKey();
  bool _sharing = false;

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

    // pickPlantImage (not a bare showImageSourceSheet+ImagePicker call) —
    // this used to skip the camera-permission check entirely, so a
    // revoked/"only this time" grant made "Take photo" here a silent dead
    // button, same class of bug as ONB-008 on Add Plant/Diagnose (see
    // pickPlantImage's own docstring).
    final file = await pickPlantImage(context);
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

  /// Lets the user pick one of the app's bundled backgrounds or a photo
  /// from their own gallery — not tier-gated (see the backend's
  /// set_growth_background), so this works even before upgrading.
  Future<void> _handleChangeBackground() async {
    final appState = context.read<AppState>();
    final plant = appState.growthJourneyPlant;
    if (plant == null) return;

    final choice = await showModalBottomSheet<_BackgroundChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BackgroundPickerSheet(current: plant.growthBackground),
    );
    if (choice == null) return;

    String? imageBase64;
    if (choice.fromGallery) {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1024);
      if (file == null) return;
      imageBase64 = base64Encode(await File(file.path).readAsBytes());
    }

    try {
      final newValue = await appState.api.setGrowthBackground(
        appState.token!,
        plant.id,
        preset: choice.presetKey,
        imageBase64: imageBase64,
      );
      appState.updatePlantLocally(plant.copyWith(growthBackground: newValue));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update the background. Try again.')));
      }
    }
  }

  /// Renders a purpose-built portrait card (not a screenshot of this
  /// screen) off-screen, captures it to a PNG, and hands that file to the
  /// OS share sheet via share_plus. Everything happens on-device: no
  /// backend call, nothing about this plant ever becomes reachable by a
  /// stranger — the image only goes wherever the user explicitly picks in
  /// the share sheet (Instagram Stories, WhatsApp, Save to Photos, ...),
  /// same trust boundary as sharing any other photo from the gallery.
  /// This is the approach recommended over a public web page specifically
  /// because it adds no new privacy surface and reaches every share
  /// destination at once instead of building one platform's deep link at
  /// a time.
  ///
  /// Capture technique: _GrowthShareCard below is inserted into an
  /// Overlay (so it's genuinely laid out and painted — unlike an Offstage
  /// subtree, which never paints at all) positioned far outside the
  /// visible screen, wrapped in a RepaintBoundary. Once it's painted,
  /// RenderRepaintBoundary.toImage() reads that layer straight to a
  /// bitmap — pixelRatio: 3 for a sharp ~1080px-wide PNG regardless of
  /// the device's own screen density. The cover photo is precached first
  /// so the overlay's first paint already has it, instead of capturing a
  /// loading placeholder.
  Future<void> _handleShare() async {
    final appState = context.read<AppState>();
    final plant = appState.growthJourneyPlant;
    if (plant == null || _sharing) return;
    setState(() => _sharing = true);

    final coverUrl = _memories.isNotEmpty ? _memories.last.photoUrl : plant.photoUrl;
    if (coverUrl != null && coverUrl.isNotEmpty) {
      try {
        await precacheImage(NetworkImage(coverUrl), context);
      } catch (e) {
        debugPrint('Could not precache the share card\'s cover photo (continuing anyway): $e');
      }
    }
    if (!mounted) return;

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        left: -10000, // painted (so it can be captured), nowhere near the visible viewport
        top: 0,
        child: Material(
          color: Colors.transparent,
          child: RepaintBoundary(
            key: _shareCardKey,
            child: _GrowthShareCard(plant: plant, coverUrl: coverUrl, memoryCount: _memories.length),
          ),
        ),
      ),
    );
    overlay.insert(entry);

    try {
      // One extra frame so the just-inserted overlay entry has actually
      // painted before capture — doing both in the same frame can race
      // ahead of that first real paint.
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;

      final boundary = _shareCardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('Could not encode the share card image');

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/vanya_growth_${plant.id}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

      appState.trackEvent('growth_journey_shared');
      await Share.shareXFiles([XFile(file.path)], text: '${plant.nickname}\'s growth journey, tracked with VANYA 🌿');
    } catch (e) {
      debugPrint('Failed to build/share the growth card: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create the share card. Try again.')));
      }
    } finally {
      entry.remove();
      if (mounted) setState(() => _sharing = false);
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
            tooltip: 'Share this journey',
            onPressed: plant == null || _sharing ? null : _handleShare,
            icon: _sharing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                : const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: 'Change background',
            onPressed: plant == null ? null : _handleChangeBackground,
            icon: const Icon(Icons.wallpaper_outlined),
          ),
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
                              // growth.limit is per plant (see plans.py's
                              // GROWTH JOURNEY note) — _memories.length is
                              // THIS plant's own count, already loaded by
                              // _load() above. growth.count itself is an
                              // account-wide total now (the Plan screen's
                              // "saved across your garden" line), not what
                              // belongs in a single plant's own badge.
                              if (growth != null && !growth.isUnlimited)
                                Text(
                                  '${_memories.length}/${growth.limit == 0 ? "0" : growth.limit}',
                                  style: AppTypography.caption(AppColors.textSecondaryOf(context)),
                                ),
                            ],
                          ),
                        ),
                        Expanded(child: _VineView(memories: _memories, onTapNode: _openDetail, background: plant.growthBackground)),
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
  // "preset:<key>" (a bundled asset), a real photo URL (custom gallery
  // pick), or null (nothing chosen yet — falls back to no texture).
  final String? background;
  const _VineView({required this.memories, required this.onTapNode, this.background});

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
      final contentHeight = _rootHeight + _tipHeight + memories.length * _nodeSpacing + (memories.isEmpty ? 60 : 0);
      // At least the visible viewport's height, not just whatever the vine's
      // own content needs — with few/no memories, contentHeight used to be
      // far shorter than the screen, so the background (painted only within
      // this box, same height as the content) stopped partway down and left
      // a bare gap of plain scaffold color above the pot instead of the
      // chosen wallpaper filling the whole screen. The pot/root anchor stays
      // pinned to the bottom of this taller box either way (see anchors
      // below), so this only stretches the empty space above it — already
      // scrollable content (many memories) is unaffected since contentHeight
      // already exceeds the viewport there.
      final totalHeight = math.max(contentHeight, constraints.maxHeight);

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
              // back to nothing (plain scaffold background) if the chosen
              // asset/photo isn't available (or nothing's been chosen yet).
              Positioned.fill(
                child: _resolveBackground(),
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
                        _potAssetPath(),
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
                      _ReadableLabel(text: 'PLANTED', style: AppTypography.caption(AppColors.textSecondaryOf(context))),
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
                    child: _ReadableLabel(
                      text: 'No memories yet — tap + to add the first one.',
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
                        _ReadableLabel(
                          text: _formatDate(memories[i].createdAt),
                          style: AppTypography.caption(AppColors.textSecondaryOf(context)),
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

  /// The chosen preset, if background is `"preset:<key>"` and that key is
  /// still a known one — null for no-background/custom-photo/an
  /// unrecognized (e.g. retired) key.
  GrowthBackgroundPreset? _currentPreset() {
    if (background == null || !background!.startsWith('preset:')) return null;
    final key = background!.substring('preset:'.length);
    for (final p in kGrowthBackgroundPresets) {
      if (p.key == key) return p;
    }
    return null;
  }

  /// null -> nothing (plain scaffold background shows through); "preset:x"
  /// -> the matching bundled asset; anything else -> treated as a real
  /// photo URL (a custom gallery pick). Either way, a load failure just
  /// falls back to nothing rather than a broken-image icon.
  Widget _resolveBackground() {
    if (background == null) {
      // Mirrors growth_pot.png's role for the pot — a neutral default so
      // the screen isn't bare before the user ever opens the picker,
      // rather than showing nothing until they make a choice.
      return Image.asset(
        'assets/images/growth_bg.jpg',
        repeat: ImageRepeat.repeatY,
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    }
    final preset = _currentPreset();
    if (background!.startsWith('preset:')) {
      if (preset == null) return const SizedBox.shrink();
      return Image.asset(
        preset.assetPath,
        repeat: ImageRepeat.repeatY,
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    }
    return Image.network(
      background!,
      repeat: ImageRepeat.repeatY,
      fit: BoxFit.fitWidth,
      alignment: Alignment.topCenter,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }

  /// The pot matches whichever background preset is chosen (an ornate urn
  /// under Gothic, a woven basket under Rainforest, ...) rather than
  /// mixing a random pot under a themed background. Falls back to the
  /// plain generic pot when there's no preset (no background chosen yet,
  /// or a custom gallery photo, which has no themed pot of its own).
  String _potAssetPath() => _currentPreset()?.potAssetPath ?? 'assets/images/growth_pot.png';
}

/// The share card itself — deliberately its own composition, not a
/// screenshot of the vine screen (which is a scrolling, interactive view
/// with edit affordances that make no sense in a shared image). Reuses
/// the same background preset and decorative type treatment
/// (unifrakturMaguntia) as the rest of Growth Journey so a shared card
/// reads as unmistakably "from VANYA" rather than a generic template.
/// Built at a fixed 1080x1920 logical size (a standard portrait share
/// ratio, native to Instagram/WhatsApp Stories and safe letterboxed
/// anywhere else) — see _handleShare's docstring for how this gets
/// captured to a PNG.
class _GrowthShareCard extends StatelessWidget {
  final Plant plant;
  final String? coverUrl;
  final int memoryCount;
  const _GrowthShareCard({required this.plant, required this.coverUrl, required this.memoryCount});

  GrowthBackgroundPreset? _preset() {
    final bg = plant.growthBackground;
    if (bg == null || !bg.startsWith('preset:')) return null;
    final key = bg.substring('preset:'.length);
    for (final p in kGrowthBackgroundPresets) {
      if (p.key == key) return p;
    }
    return null;
  }

  String _daysGrowingLabel() {
    final days = DateTime.now().difference(plant.createdAt).inDays;
    if (days < 1) return 'Just started';
    if (days == 1) return '1 day growing';
    return '$days days growing';
  }

  @override
  Widget build(BuildContext context) {
    final preset = _preset();
    return SizedBox(
      width: 1080,
      height: 1920,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primaryTintPairOf(context).$2, AppColors.primary, AppColors.primaryDark],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The plant's own chosen Growth Journey backdrop, if it picked
            // one — ties the card back to the actual screen it came from,
            // same reasoning as reusing the pot/theme system elsewhere.
            if (preset != null)
              Opacity(
                opacity: 0.55,
                child: Image.asset(preset.assetPath, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.15), Colors.black.withValues(alpha: 0.55)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 140, 72, 96),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 340,
                        height: 340,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 6),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 40, offset: Offset(0, 16))],
                        ),
                        padding: const EdgeInsets.all(6),
                        child: ClipOval(child: PlantImage(url: coverUrl, borderRadius: 999)),
                      ),
                      const SizedBox(height: 48),
                      Text(
                        plant.nickname,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.unifrakturMaguntia(fontSize: 76, color: Colors.white, height: 1.15),
                      ),
                      if (plant.species != null && plant.species!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          plant.species!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 30, fontStyle: FontStyle.italic, color: Colors.white70),
                        ),
                      ],
                    ],
                  ),
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          '${_daysGrowingLabel()} · $memoryCount ${memoryCount == 1 ? "memory" : "memories"}',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 26, color: Colors.white, letterSpacing: 0.5),
                        ),
                      ),
                      const SizedBox(height: 40),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.eco, color: Colors.white, size: 30),
                          const SizedBox(width: 10),
                          Text(
                            'VANYA · every plant has a story',
                            style: TextStyle(fontSize: 24, color: Colors.white.withValues(alpha: 0.9), letterSpacing: 0.3),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small opaque-ish backdrop behind any text sitting directly on top of a
/// background photo/texture — was originally just the date labels'
/// pattern (the stem's curve sometimes passes right behind one), pulled
/// out and reused for "PLANTED" and the empty-state message too, which
/// used to be bare Text and genuinely unreadable against several of the
/// darker bundled backgrounds (Gothic Botanical, Forest Dusk, Rainforest —
/// see kGrowthBackgroundPresets) since textSecondaryOf(context) is a
/// muted, low-contrast color chosen for a plain scaffold background, not
/// an arbitrary photo behind it.
class _ReadableLabel extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign? textAlign;
  const _ReadableLabel({required this.text, required this.style, this.textAlign});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.bgOf(context).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(text, style: style, textAlign: textAlign),
    );
  }
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
              // BUG: Save memory's onPressed reads _nameController.text at
              // build time, but nothing was ever wired to rebuild this
              // sheet when that text changed — so it stayed disabled
              // (evaluated once, against the initial empty text) no matter
              // what got typed. onChanged forces the rebuild that was
              // missing.
              onChanged: (_) => setState(() {}),
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

/// What the picker sheet resolves to — exactly one of the two, mirroring
/// GrowthBackgroundInput's "exactly one of preset/image_base64" contract
/// on the backend.
class _BackgroundChoice {
  final String? presetKey;
  final bool fromGallery;
  const _BackgroundChoice.preset(this.presetKey) : fromGallery = false;
  const _BackgroundChoice.gallery()
      : presetKey = null,
        fromGallery = true;
}

class _BackgroundPickerSheet extends StatelessWidget {
  final String? current;
  const _BackgroundPickerSheet({required this.current});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
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
          Text('Choose a background', style: AppTypography.h2(AppColors.textOf(context))),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
            children: [
              for (final preset in kGrowthBackgroundPresets)
                _PresetTile(
                  preset: preset,
                  selected: current == 'preset:${preset.key}',
                  onTap: () => Navigator.of(context).pop(_BackgroundChoice.preset(preset.key)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.primaryTintPairOf(context).$1, borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: Icon(Icons.photo_library_outlined, size: 18, color: AppColors.primaryTintPairOf(context).$2),
            ),
            title: Text('Choose from your photos', style: AppTypography.bodyStrong(AppColors.textOf(context))),
            onTap: () => Navigator.of(context).pop(const _BackgroundChoice.gallery()),
          ),
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final GrowthBackgroundPreset preset;
  final bool selected;
  final VoidCallback onTap;
  const _PresetTile({required this.preset, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: selected ? AppColors.primary : AppColors.borderOf(context), width: selected ? 2.5 : 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                preset.assetPath,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(color: preset.swatchColor),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            preset.label,
            style: AppTypography.caption(AppColors.textSecondaryOf(context)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
