import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../theme.dart';

/// One row of the "Appareils et sessions" list in Sécurité: which session
/// this is, when the SDK last saw it, and what the user can do about it.
class DeviceRow extends StatelessWidget {
  const DeviceRow({
    super.key,
    required this.device,
    this.serverSession,
    required this.isThisDevice,
    required this.verifying,
    required this.onVerify,
    required this.onMarkVerified,
    required this.onMarkUnverified,
  });

  final DeviceKeys device;

  /// The homeserver's own record for this session (`GET /devices`): carries
  /// the last seen IP address and timestamp, which the SDK's local copy does
  /// not have. Null when the history could not be fetched.
  final Device? serverSession;

  /// True for the session running on this phone: it cannot verify itself.
  final bool isThisDevice;

  /// True while an emoji comparison with this device is in flight.
  final bool verifying;
  final VoidCallback onVerify;
  final VoidCallback onMarkVerified;
  final VoidCallback onMarkUnverified;

  @override
  Widget build(BuildContext context) {
    final rawName = device.deviceDisplayName?.trim();
    final label = (rawName == null || rawName.isEmpty)
        ? 'Appareil sans nom'
        : rawName;
    final verified = device.verified;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isThisDevice ? Icons.smartphone : Icons.devices_other_outlined,
                size: 20,
                color: verified ? WaPalette.accent : WaPalette.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isThisDevice ? '$label (ce téléphone)' : label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: verified
                      ? WaPalette.accent.withValues(alpha: 0.14)
                      : const Color(0xFFF3E7C8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  verified ? 'Vérifié' : 'Non vérifié',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: verified
                        ? WaPalette.accent
                        : const Color(0xFF8A6D1F),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Identifiant : ${device.deviceId ?? '—'} · Vu pour la dernière '
            'fois : $_lastSeenLabel',
            style: TextStyle(fontSize: 12, color: WaPalette.textSecondary),
          ),
          if (_lastSeenIp != null)
            Text(
              'Dernière adresse IP : $_lastSeenIp',
              style: TextStyle(fontSize: 12, color: WaPalette.textSecondary),
            ),
          if (!isThisDevice)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: verifying ? null : onVerify,
                  child: verifying
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Vérifier'),
                ),
                verified
                    ? TextButton(
                        onPressed: onMarkUnverified,
                        child: const Text('Retirer la vérification'),
                      )
                    : TextButton(
                        onPressed: onMarkVerified,
                        child: const Text('Marquer vérifié'),
                      ),
              ],
            ),
        ],
      ),
    );
  }

  /// Prefers the homeserver's timestamp over the SDK's local guess.
  String get _lastSeenLabel {
    final serverTs = serverSession?.lastSeenTs;
    if (serverTs != null && serverTs > 0) {
      return _formatLastSeen(
        DateTime.fromMillisecondsSinceEpoch(serverTs),
      );
    }
    return _formatLastSeen(device.lastActive);
  }

  String? get _lastSeenIp => serverSession?.lastSeenIp;

  /// Best-effort "last seen" from the SDK's own clock; the value is the time
  /// this session last talked to one of our devices, not a server record.
  static String _formatLastSeen(DateTime when) {
    if (when.millisecondsSinceEpoch <= 0) return 'jamais';
    final delta = DateTime.now().difference(when);
    if (delta.inMinutes < 1) return "à l'instant";
    if (delta.inHours < 1) return 'il y a ${delta.inMinutes} min';
    if (delta.inDays < 1) return 'il y a ${delta.inHours} h';
    return 'le ${when.day}/${when.month}/${when.year}';
  }
}
