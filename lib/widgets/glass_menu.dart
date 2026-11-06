import 'package:flutter/cupertino.dart';

import '../theme/tokens.dart';
import 'controls.dart';

/// One thing in a menu: what it's called, its icon and colour, and how many
/// new things wait behind it.
class MenuEntry {
  const MenuEntry(
    this.label,
    this.icon,
    this.onTap, {
    this.colour,
    this.count = 0,
    this.destructive = false,
    this.indent = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? colour;
  final int count;
  final bool destructive;

  /// Sits under the entry above it, such as a saved group chat.
  final bool indent;
}

class MenuSection {
  const MenuSection(this.title, this.entries);

  final String title;
  final List<MenuEntry> entries;
}

/// One row: a glass square with the icon, the label, a red count, a chevron.
class GlassMenuRow extends StatefulWidget {
  const GlassMenuRow({
    super.key,
    required this.entry,
    this.dense = false,
    this.onDone,
  });

  final MenuEntry entry;

  /// Smaller, for the sidebar.
  final bool dense;

  /// Runs before the entry's action, such as closing the sheet it's in.
  final VoidCallback? onDone;

  @override
  State<GlassMenuRow> createState() => _GlassMenuRowState();
}

class _GlassMenuRowState extends State<GlassMenuRow> {
  var _hover = false;
  var _down = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final e = widget.entry;
    final colour = e.destructive ? p.blocked : (e.colour ?? p.accent);
    final square = widget.dense ? 28.0 : 32.0;
    return Semantics(
      button: true,
      label: e.count > 0 ? '${e.label}, ${e.count} new' : e.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: () {
            widget.onDone?.call();
            e.onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            margin: EdgeInsets.only(left: e.indent ? 22 : 0),
            padding: EdgeInsets.symmetric(
              horizontal: widget.dense ? 8 : 10,
              vertical: widget.dense ? 6 : 8,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: _down
                  ? p.control
                  : (_hover
                        ? p.control.withValues(alpha: p.control.a * 0.6)
                        : const Color(0x00000000)),
            ),
            child: Row(
              children: [
                Container(
                  width: square,
                  height: square,
                  decoration: glassTint(p, colour, radius: square * 0.32),
                  child: Icon(e.icon, size: square * 0.56, color: colour),
                ),
                SizedBox(width: widget.dense ? 10 : 12),
                Expanded(
                  child: Text(
                    e.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (widget.dense
                                ? TypeRamp.label(
                                    e.destructive ? p.blocked : p.ink,
                                  )
                                : TypeRamp.body(
                                    e.destructive ? p.blocked : p.ink,
                                  ))
                            .weighted(FontWeight.w500),
                  ),
                ),
                if (e.count > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5262B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      e.count > 99 ? '99+' : '${e.count}',
                      textAlign: TextAlign.center,
                      style: TypeRamp.caption(const Color(0xFFFFFFFF))
                          .weighted(FontWeight.w700),
                    ),
                  ),
                if (!widget.dense) ...[
                  const SizedBox(width: 6),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 13,
                    color: p.inkFaint,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sections of glass rows, for a menu sheet or the side panel.
class GlassMenuList extends StatelessWidget {
  const GlassMenuList({
    super.key,
    required this.sections,
    this.dense = false,
    this.onDone,
  });

  final List<MenuSection> sections;
  final bool dense;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in sections)
          if (s.entries.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                dense ? 10 : 6,
                dense ? 12 : 14,
                6,
                dense ? 4 : 6,
              ),
              child: Text(
                s.title.toUpperCase(),
                style: TypeRamp.caption(p.inkFaint)
                    .weighted(FontWeight.w700)
                    .copyWith(letterSpacing: 0.8),
              ),
            ),
            if (dense)
              for (final e in s.entries)
                GlassMenuRow(entry: e, dense: true, onDone: onDone)
            else
              GlassPanel(
                radius: 18,
                weight: GlassWeight.thin,
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, e) in s.entries.indexed) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 54),
                          child: Container(height: 0.5, color: p.hairline),
                        ),
                      GlassMenuRow(entry: e, onDone: onDone),
                    ],
                  ],
                ),
              ),
          ],
      ],
    );
  }
}

/// A person's first letter in a small tinted pane of glass. Their colour stays
/// the same wherever they appear.
class GlassAvatar extends StatelessWidget {
  const GlassAvatar({super.key, required this.name, this.size = 30});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tints = [
      p.accent,
      p.accentWarm,
      p.accentTeal,
      p.accentViolet,
      p.route,
      p.done,
    ];
    final colour =
        tints[name.codeUnits.fold<int>(0, (a, b) => a + b) % tints.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: glassTint(p, colour, radius: size / 2),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TypeRamp.caption(p.ink)
            .weighted(FontWeight.w700)
            .copyWith(fontSize: size * 0.42),
      ),
    );
  }
}
