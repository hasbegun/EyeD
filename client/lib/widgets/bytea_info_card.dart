import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/db_inspector_models.dart';

class ByteaInfoCard extends StatelessWidget {
  final String columnName;
  final ByteaInfo info;

  const ByteaInfoCard({
    super.key,
    required this.columnName,
    required this.info,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isHe = info.format == 'hev1';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  isHe ? Icons.lock : Icons.archive,
                  size: 16,
                  color: isHe ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  columnName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                _FormatBadge(format: info.format),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),

          // Details
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(label: 'Size', value: info.humanSize),
                _DetailRow(
                  label: 'Format',
                  value: isHe
                      ? 'HEv1 (BFV ciphertexts)'
                      : info.format == 'npz'
                          ? 'NPZ (NumPy compressed)'
                          : 'Unknown',
                ),
                if (isHe && info.heCiphertextCount != null)
                  _DetailRow(
                    label: 'Ciphertexts',
                    value: '${info.heCiphertextCount}',
                  ),
                if (isHe && info.hePerCtSizes != null)
                  _DetailRow(
                    label: 'Per-CT sizes',
                    value: info.hePerCtSizes!
                        .map((s) => '${(s / 1024).toStringAsFixed(0)} KB')
                        .join(' | '),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Hex prefix:',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: info.prefixHex));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copied hex prefix'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Icon(Icons.copy, size: 14, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatHex(info.prefixHex),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatHex(String hex) {
    final buf = StringBuffer();
    for (int i = 0; i < hex.length; i += 2) {
      if (i > 0) buf.write(' ');
      buf.write(hex.substring(i, i + 2 > hex.length ? hex.length : i + 2));
    }
    return buf.toString();
  }
}

class _FormatBadge extends StatelessWidget {
  final String format;

  const _FormatBadge({required this.format});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isHe = format == 'hev1';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isHe
            ? cs.primary.withValues(alpha: 0.15)
            : cs.onSurfaceVariant.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isHe ? 'HEv1' : format.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isHe ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact inline chip for BYTEA in table rows.
class ByteaChip extends StatelessWidget {
  final ByteaInfo info;

  const ByteaChip({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isHe = info.format == 'hev1';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isHe
            ? cs.primary.withValues(alpha: 0.12)
            : cs.onSurfaceVariant.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isHe) ...[
            Icon(Icons.lock, size: 10, color: cs.primary),
            const SizedBox(width: 3),
          ],
          Text(
            isHe
                ? 'HEv1 ${info.heCiphertextCount ?? ""} cts ${info.humanSize}'
                : '${info.format.toUpperCase()} ${info.humanSize}',
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: isHe ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
