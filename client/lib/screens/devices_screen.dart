import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/device_provider.dart';
import '../widgets/status_indicator.dart';
import '../widgets/video_feed.dart';

class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final devices = ref.watch(deviceMapProvider);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.devices,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: devices.isEmpty
              ? Center(
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: cs.outlineVariant,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Text(
                      l10n.noDevicesDetected,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount =
                        (constraints.maxWidth / 420).floor().clamp(1, 4);
                    return GridView.builder(
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.1,
                      ),
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final device = devices.values.toList()[index];
                        return _DeviceCard(device: device);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final DeviceInfo device;

  const _DeviceCard({required this.device});

  bool get _isActive =>
      DateTime.now().difference(device.lastSeen).inSeconds < 10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final lastResult = device.lastResult;
    final hd = lastResult?.match?.hammingDistance;
    final latency = lastResult?.latencyMs;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    device.id,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                StatusIndicator(connected: _isActive),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),

          // Video
          Expanded(child: VideoFeed(deviceId: device.id)),

          // Metadata
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                _MetaLabel(l10n.frames, device.frameCount.toString()),
                const Spacer(),
                _MetaLabel(l10n.hd, hd != null ? hd.toStringAsFixed(3) : '-'),
                const Spacer(),
                _MetaLabel(
                    l10n.latency, latency != null ? '${latency.round()}ms' : '-'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaLabel extends StatelessWidget {
  final String label;
  final String value;

  const _MetaLabel(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: cs.onSurface,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
