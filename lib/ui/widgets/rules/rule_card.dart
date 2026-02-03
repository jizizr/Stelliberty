import 'package:flutter/material.dart';
import 'package:stelliberty/clash/model/rule_model.dart';

class RuleCard extends StatelessWidget {
  final int index;
  final RuleItem rule;

  const RuleCard({super.key, required this.index, required this.rule});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final mixColor = isDark ? Colors.black : Colors.white;
    final mixOpacity = 0.1;

    final proxyColor = _getProxyColor(colorScheme, rule.proxy);
    final badgeColor = proxyColor;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Color.alphaBlend(
          mixColor.withValues(alpha: mixOpacity),
          colorScheme.surface.withValues(alpha: isDark ? 0.7 : 0.85),
        ),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 32,
              child: Center(
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      index.toString(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    rule.payload.isEmpty ? '-' : rule.payload,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        rule.type,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          rule.proxy,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: proxyColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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

  Color _getProxyColor(ColorScheme colorScheme, String proxy) {
    final upper = proxy.toUpperCase();
    if (upper == 'REJECT' || upper == 'REJECT-DROP') {
      return colorScheme.error;
    }
    if (upper == 'DIRECT') {
      return colorScheme.onSurface;
    }

    final palette = <Color>[
      colorScheme.primary,
      colorScheme.secondary,
      colorScheme.tertiary,
      colorScheme.error,
    ];

    var sum = 0;
    for (final codeUnit in proxy.codeUnits) {
      sum += codeUnit;
    }

    return palette[sum % palette.length];
  }
}
