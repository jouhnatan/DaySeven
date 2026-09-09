/// A searchable, curated set of characters that are absent from typical
/// keyboards but useful in prose, notation, and world-building documents.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/theme.dart';

@immutable
class SpecialCharacter {
  const SpecialCharacter(this.character, this.name);

  final String character;
  final String name;
}

const specialCharacters = <SpecialCharacter>[
  SpecialCharacter('—', 'Em dash'),
  SpecialCharacter('–', 'En dash'),
  SpecialCharacter('…', 'Horizontal ellipsis'),
  SpecialCharacter('‘', 'Left single quotation mark'),
  SpecialCharacter('’', 'Right single quotation mark'),
  SpecialCharacter('“', 'Left double quotation mark'),
  SpecialCharacter('”', 'Right double quotation mark'),
  SpecialCharacter('‚', 'Single low-9 quotation mark'),
  SpecialCharacter('„', 'Double low-9 quotation mark'),
  SpecialCharacter('•', 'Bullet'),
  SpecialCharacter('·', 'Middle dot'),
  SpecialCharacter('′', 'Prime'),
  SpecialCharacter('″', 'Double prime'),
  SpecialCharacter('†', 'Dagger'),
  SpecialCharacter('‡', 'Double dagger'),
  SpecialCharacter('§', 'Section sign'),
  SpecialCharacter('¶', 'Pilcrow sign'),
  SpecialCharacter('©', 'Copyright sign'),
  SpecialCharacter('®', 'Registered sign'),
  SpecialCharacter('™', 'Trade mark sign'),
  SpecialCharacter('№', 'Numero sign'),
  SpecialCharacter('°', 'Degree sign'),
  SpecialCharacter('¢', 'Cent sign'),
  SpecialCharacter('£', 'Pound sign'),
  SpecialCharacter('¥', 'Yen sign'),
  SpecialCharacter('€', 'Euro sign'),
  SpecialCharacter('₹', 'Indian rupee sign'),
  SpecialCharacter('₩', 'Won sign'),
  SpecialCharacter('₽', 'Ruble sign'),
  SpecialCharacter('₿', 'Bitcoin sign'),
  SpecialCharacter('₫', 'Dong sign'),
  SpecialCharacter('₴', 'Hryvnia sign'),
  SpecialCharacter('±', 'Plus-minus sign'),
  SpecialCharacter('×', 'Multiplication sign'),
  SpecialCharacter('÷', 'Division sign'),
  SpecialCharacter('≠', 'Not equal to'),
  SpecialCharacter('≈', 'Almost equal to'),
  SpecialCharacter('≤', 'Less-than or equal to'),
  SpecialCharacter('≥', 'Greater-than or equal to'),
  SpecialCharacter('∞', 'Infinity'),
  SpecialCharacter('√', 'Square root'),
  SpecialCharacter('∛', 'Cube root'),
  SpecialCharacter('∑', 'N-ary summation'),
  SpecialCharacter('∏', 'N-ary product'),
  SpecialCharacter('∫', 'Integral'),
  SpecialCharacter('∂', 'Partial differential'),
  SpecialCharacter('∆', 'Increment'),
  SpecialCharacter('∇', 'Nabla'),
  SpecialCharacter('∝', 'Proportional to'),
  SpecialCharacter('∈', 'Element of'),
  SpecialCharacter('∉', 'Not an element of'),
  SpecialCharacter('∅', 'Empty set'),
  SpecialCharacter('∩', 'Intersection'),
  SpecialCharacter('∪', 'Union'),
  SpecialCharacter('∧', 'Logical and'),
  SpecialCharacter('∨', 'Logical or'),
  SpecialCharacter('←', 'Leftwards arrow'),
  SpecialCharacter('↑', 'Upwards arrow'),
  SpecialCharacter('→', 'Rightwards arrow'),
  SpecialCharacter('↓', 'Downwards arrow'),
  SpecialCharacter('↔', 'Left right arrow'),
  SpecialCharacter('↕', 'Up down arrow'),
  SpecialCharacter('↖', 'North west arrow'),
  SpecialCharacter('↗', 'North east arrow'),
  SpecialCharacter('↘', 'South east arrow'),
  SpecialCharacter('↙', 'South west arrow'),
  SpecialCharacter('⇐', 'Leftwards double arrow'),
  SpecialCharacter('⇒', 'Rightwards double arrow'),
  SpecialCharacter('⇔', 'Left right double arrow'),
  SpecialCharacter('↦', 'Rightwards arrow from bar'),
  SpecialCharacter('½', 'Vulgar fraction one half'),
  SpecialCharacter('⅓', 'Vulgar fraction one third'),
  SpecialCharacter('⅔', 'Vulgar fraction two thirds'),
  SpecialCharacter('¼', 'Vulgar fraction one quarter'),
  SpecialCharacter('¾', 'Vulgar fraction three quarters'),
  SpecialCharacter('⅛', 'Vulgar fraction one eighth'),
  SpecialCharacter('⅜', 'Vulgar fraction three eighths'),
  SpecialCharacter('⅝', 'Vulgar fraction five eighths'),
  SpecialCharacter('⅞', 'Vulgar fraction seven eighths'),
  SpecialCharacter('¹', 'Superscript one'),
  SpecialCharacter('²', 'Superscript two'),
  SpecialCharacter('³', 'Superscript three'),
  SpecialCharacter('ⁿ', 'Superscript Latin small letter n'),
  SpecialCharacter('₀', 'Subscript zero'),
  SpecialCharacter('₁', 'Subscript one'),
  SpecialCharacter('₂', 'Subscript two'),
  SpecialCharacter('₃', 'Subscript three'),
  SpecialCharacter('₄', 'Subscript four'),
  SpecialCharacter('₅', 'Subscript five'),
  SpecialCharacter('₆', 'Subscript six'),
  SpecialCharacter('₇', 'Subscript seven'),
  SpecialCharacter('₈', 'Subscript eight'),
  SpecialCharacter('₉', 'Subscript nine'),
  SpecialCharacter('α', 'Greek small letter alpha'),
  SpecialCharacter('β', 'Greek small letter beta'),
  SpecialCharacter('γ', 'Greek small letter gamma'),
  SpecialCharacter('δ', 'Greek small letter delta'),
  SpecialCharacter('ε', 'Greek small letter epsilon'),
  SpecialCharacter('θ', 'Greek small letter theta'),
  SpecialCharacter('λ', 'Greek small letter lambda'),
  SpecialCharacter('μ', 'Greek small letter mu'),
  SpecialCharacter('π', 'Greek small letter pi'),
  SpecialCharacter('ρ', 'Greek small letter rho'),
  SpecialCharacter('σ', 'Greek small letter sigma'),
  SpecialCharacter('τ', 'Greek small letter tau'),
  SpecialCharacter('φ', 'Greek small letter phi'),
  SpecialCharacter('χ', 'Greek small letter chi'),
  SpecialCharacter('ψ', 'Greek small letter psi'),
  SpecialCharacter('ω', 'Greek small letter omega'),
  SpecialCharacter('Δ', 'Greek capital letter delta'),
  SpecialCharacter('Ω', 'Greek capital letter omega'),
  SpecialCharacter('✓', 'Check mark'),
  SpecialCharacter('✗', 'Ballot x'),
  SpecialCharacter('★', 'Black star'),
  SpecialCharacter('☆', 'White star'),
  SpecialCharacter('◆', 'Black diamond'),
  SpecialCharacter('◇', 'White diamond'),
  SpecialCharacter('■', 'Black square'),
  SpecialCharacter('□', 'White square'),
  SpecialCharacter('●', 'Black circle'),
  SpecialCharacter('○', 'White circle'),
  SpecialCharacter('♠', 'Black spade suit'),
  SpecialCharacter('♥', 'Black heart suit'),
  SpecialCharacter('♦', 'Black diamond suit'),
  SpecialCharacter('♣', 'Black club suit'),
  SpecialCharacter('♀', 'Female sign'),
  SpecialCharacter('♂', 'Male sign'),
];

Future<String?> showSpecialCharacterPicker(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const SpecialCharacterPicker(),
    );

class SpecialCharacterPicker extends StatefulWidget {
  const SpecialCharacterPicker({super.key});

  @override
  State<SpecialCharacterPicker> createState() => _SpecialCharacterPickerState();
}

class _SpecialCharacterPickerState extends State<SpecialCharacterPicker> {
  final _search = TextEditingController();

  List<SpecialCharacter> get _filtered {
    final query = _search.text.trim();
    if (query.isEmpty) return specialCharacters;
    final normalized = query.toLowerCase();
    return specialCharacters
        .where(
          (entry) =>
              entry.character == query ||
              entry.name.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
  }

  void _onSearchChanged() => setState(() {});

  @override
  void dispose() {
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final filtered = _filtered;

    return Dialog(
      key: const Key('special-character-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 44),
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        key: const Key('special-character-picker'),
        width: 480,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: DsSpace.ml),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Special characters',
                      style: uiHeaderTextStyle(
                        size: 16,
                        height: 22 / 16,
                        color: colors.text,
                      ),
                    ),
                  ),
                  DsButton(
                    height: DsSize.smallControl,
                    padding: const EdgeInsets.all(DsSpace.s),
                    semanticLabel: 'Close special characters',
                    onPressed: () => Navigator.of(context).pop(),
                    child: Icon(Icons.close, size: 16, color: colors.muted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(DsSpace.ml),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Search characters',
                      style: DsType.body(color: colors.text),
                    ),
                    const SizedBox(height: DsSpace.row),
                    DsField(
                      key: const Key('special-character-search'),
                      controller: _search,
                      hint: 'Name or character',
                      autofocus: true,
                      margin: EdgeInsets.zero,
                    ),
                    const SizedBox(height: DsSpace.m),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'No characters found',
                                style: DsType.caption(color: colors.muted),
                              ),
                            )
                          : Shortcuts(
                              shortcuts: const {
                                SingleActivator(
                                  LogicalKeyboardKey.arrowLeft,
                                ): DirectionalFocusIntent(
                                  TraversalDirection.left,
                                ),
                                SingleActivator(
                                  LogicalKeyboardKey.arrowRight,
                                ): DirectionalFocusIntent(
                                  TraversalDirection.right,
                                ),
                                SingleActivator(
                                  LogicalKeyboardKey.arrowUp,
                                ): DirectionalFocusIntent(
                                  TraversalDirection.up,
                                ),
                                SingleActivator(
                                  LogicalKeyboardKey.arrowDown,
                                ): DirectionalFocusIntent(
                                  TraversalDirection.down,
                                ),
                              },
                              child: FocusTraversalGroup(
                                policy: WidgetOrderTraversalPolicy(),
                                child: GridView.builder(
                                  key: const Key('special-character-grid'),
                                  padding: EdgeInsets.zero,
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 4,
                                        crossAxisSpacing: DsSpace.s,
                                        mainAxisSpacing: DsSpace.s,
                                        childAspectRatio: 1.35,
                                      ),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final entry = filtered[index];
                                    return _CharacterTile(entry: entry);
                                  },
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: DsSpace.ml),
              alignment: Alignment.centerRight,
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: DsLabelButton(
                label: 'Close',
                variant: DsButtonVariant.quiet,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterTile extends StatelessWidget {
  const _CharacterTile({required this.entry});

  final SpecialCharacter entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return DsButton(
      key: ValueKey('special-character-${entry.character}'),
      framed: true,
      padding: EdgeInsets.zero,
      semanticLabel: 'Insert ${entry.name}',
      onPressed: () => Navigator.of(context).pop(entry.character),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: Text(
                entry.character,
                style:
                    uiTextStyle(
                      size: 28,
                      height: 34 / 28,
                      color: colors.text,
                    ).copyWith(
                      // Names and controls stay in the UI face. The preview is
                      // document content, and the bundled document face has a
                      // substantially broader Unicode repertoire.
                      fontFamily: 'IBM Plex Sans',
                      fontFamilyFallback: const [
                        'Apple Symbols',
                        'Segoe UI Symbol',
                        'Arial Unicode MS',
                        'Instrument Sans',
                      ],
                    ),
              ),
            ),
          ),
          Container(height: DsSpace.seam, color: colors.border),
          SizedBox(
            height: 40,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DsSpace.xs),
                child: Text(
                  entry.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: DsType.caption(color: colors.muted),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
