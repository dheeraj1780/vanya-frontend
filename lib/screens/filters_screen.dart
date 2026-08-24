import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';

/// Smart Filters — was a "Filter" link on Home that did nothing (`onTap:
/// () {}`), then a full pushed screen. Now a blurred modal sheet over the
/// current screen instead: no full-screen navigation for what's fundamentally
/// a quick, in-place refinement of the plant grid you're already looking at.
/// The backend already supports every one of these as a query param on
/// GET /plants (see api/client.dart's listPlants).
Future<void> showFiltersSheet(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Filters',
    barrierColor: Colors.transparent, // the blur itself does the dimming, painted in transitionBuilder below
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, animation, secondaryAnimation) => const SizedBox.shrink(),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      // showGeneralDialog renders this straight into the navigator's overlay,
      // with no Scaffold/Material ancestor above it — but ChoiceChip (and the
      // TextButton/IconButton in the sheet header) need one. Transparency
      // type so it doesn't paint its own opaque surface over the blur/sheet.
      return Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: FadeTransition(
                opacity: curved,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(color: AppColors.primaryDark.withValues(alpha: 0.28)),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
                child: const _FiltersSheetContent(),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _FiltersSheetContent extends StatefulWidget {
  const _FiltersSheetContent();
  @override
  State<_FiltersSheetContent> createState() => _FiltersSheetContentState();
}

class _FiltersSheetContentState extends State<_FiltersSheetContent> {
  bool? _isIndoor;
  bool? _isPetSafe;
  bool? _isAirPurifying;
  String? _careDifficulty;
  String? _lightNeeds;

  List<String> _lightNeedsOptions = [];
  bool _loadingOptions = true;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _isIndoor = appState.filterIsIndoor;
    _isPetSafe = appState.filterIsPetSafe;
    _isAirPurifying = appState.filterIsAirPurifying;
    _careDifficulty = appState.filterCareDifficulty;
    _lightNeeds = appState.filterLightNeeds;
    _loadLightNeedsOptions();
  }

  /// light_needs is free text set by the AI at identify time (not a fixed
  /// enum), so the option list is built from this user's own plants rather
  /// than a guessed static list — otherwise most options would never
  /// actually match anything. Fetched unfiltered so options don't shrink
  /// as filters narrow the results.
  Future<void> _loadLightNeedsOptions() async {
    final appState = context.read<AppState>();
    try {
      final allPlants = await appState.api.listPlants(appState.token!);
      final options = allPlants.map((p) => p.lightNeeds).whereType<String>().toSet().toList()..sort();
      if (mounted) setState(() => _lightNeedsOptions = options);
    } catch (e) {
      debugPrint('Failed to load light-needs filter options: $e');
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  void _clearAll() {
    setState(() {
      _isIndoor = null;
      _isPetSafe = null;
      _isAirPurifying = null;
      _careDifficulty = null;
      _lightNeeds = null;
    });
  }

  Future<void> _apply() async {
    final appState = context.read<AppState>();
    await appState.applyFilters(
      isIndoor: _isIndoor,
      isPetSafe: _isPetSafe,
      isAirPurifying: _isAirPurifying,
      careDifficulty: _careDifficulty,
      lightNeeds: _lightNeeds,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 30, offset: const Offset(0, -6))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Filter plants', style: AppTypography.h2(AppColors.textOf(context))),
                  Row(
                    children: [
                      TextButton(onPressed: _clearAll, child: const Text('Clear all')),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close, size: 20, color: AppColors.textSecondaryOf(context)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                shrinkWrap: true,
                children: [
                  _FilterSection(
                    label: 'Location',
                    child: _TriStateChips(value: _isIndoor, trueLabel: 'Indoor', falseLabel: 'Outdoor', onChanged: (v) => setState(() => _isIndoor = v)),
                  ),
                  _FilterSection(
                    label: 'Pet safety',
                    child: _TriStateChips(value: _isPetSafe, trueLabel: 'Pet-safe', falseLabel: 'Not pet-safe', onChanged: (v) => setState(() => _isPetSafe = v)),
                  ),
                  _FilterSection(
                    label: 'Air purifying',
                    child: _TriStateChips(value: _isAirPurifying, trueLabel: 'Air-purifying', falseLabel: 'Not air-purifying', onChanged: (v) => setState(() => _isAirPurifying = v)),
                  ),
                  _FilterSection(
                    label: 'Care difficulty',
                    child: Wrap(
                      spacing: 8,
                      children: [
                        _OptionChip(label: 'All', selected: _careDifficulty == null, onTap: () => setState(() => _careDifficulty = null)),
                        for (final level in const ['easy', 'moderate', 'hard'])
                          _OptionChip(
                            label: level[0].toUpperCase() + level.substring(1),
                            selected: _careDifficulty == level,
                            onTap: () => setState(() => _careDifficulty = level),
                          ),
                      ],
                    ),
                  ),
                  _FilterSection(
                    label: 'Light needs',
                    child: _loadingOptions
                        ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Loading…'))
                        : _lightNeedsOptions.isEmpty
                            ? Text('No plants with recorded light needs yet.', style: AppTypography.body(AppColors.textSecondaryOf(context)))
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _OptionChip(label: 'All', selected: _lightNeeds == null, onTap: () => setState(() => _lightNeeds = null)),
                                  for (final option in _lightNeedsOptions)
                                    _OptionChip(label: option, selected: _lightNeeds == option, onTap: () => setState(() => _lightNeeds = option)),
                                ],
                              ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: PrimaryButton(label: 'Apply filters', onPressed: _apply),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  final String label;
  final Widget child;
  const _FilterSection({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: AppTypography.eyebrow(AppColors.textSecondaryOf(context))),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}

/// All / true / false chip group for the nullable bool filters.
class _TriStateChips extends StatelessWidget {
  final bool? value;
  final String trueLabel;
  final String falseLabel;
  final ValueChanged<bool?> onChanged;
  const _TriStateChips({required this.value, required this.trueLabel, required this.falseLabel, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        _OptionChip(label: 'All', selected: value == null, onTap: () => onChanged(null)),
        _OptionChip(label: trueLabel, selected: value == true, onTap: () => onChanged(true)),
        _OptionChip(label: falseLabel, selected: value == false, onTap: () => onChanged(false)),
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _OptionChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (tint, tintFg) = AppColors.primaryTintPairOf(context);
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: tint,
      labelStyle: TextStyle(color: selected ? tintFg : AppColors.textOf(context), fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
      side: BorderSide(color: selected ? tintFg : AppColors.borderOf(context)),
    );
  }
}
