import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../theme.dart';

/// The WhatsApp-style circular avatar: the room or user photo when one is
/// reachable, otherwise a coloured circle carrying the display initial.
///
/// Photos are fetched through [Client.getContentThumbnail] rather than a bare
/// network image because Matrix media is authenticated — a plain URL would be
/// rejected with 401 by a well-configured homeserver.
class MatrixAvatar extends StatefulWidget {
  const MatrixAvatar({
    super.key,
    required this.name,
    required this.avatarUri,
    required this.client,
    this.size = 52,
  });

  final String name;
  final Uri? avatarUri;
  final Client? client;
  final double size;

  @override
  State<MatrixAvatar> createState() => _MatrixAvatarState();
}

class _MatrixAvatarState extends State<MatrixAvatar> {
  late final Future<Uint8List?> _image;

  @override
  void initState() {
    super.initState();
    _image = _load();
  }

  @override
  void didUpdateWidget(MatrixAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUri != widget.avatarUri ||
        oldWidget.client != widget.client) {
      _image = _load();
    }
  }

  Future<Uint8List?> _load() async {
    final uri = widget.avatarUri;
    final client = widget.client;
    if (uri == null || client == null) return null;
    // `mxc://server/mediaId` has to be split: the API wants the two parts.
    if (uri.scheme != 'mxc' || uri.host.isEmpty || uri.pathSegments.isEmpty) {
      return null;
    }
    final pixels = widget.size.ceil();
    try {
      final response = await client.getContentThumbnail(
        uri.host,
        uri.pathSegments.first,
        pixels,
        pixels,
      );
      return response.data;
    } catch (_) {
      return null;
    }
  }

  /// Picks a stable colour so a user keeps the same hue across restarts.
  Color get _color {
    final source = widget.name;
    var hash = 0;
    for (var i = 0; i < source.length; i++) {
      hash = (hash * 31 + source.codeUnitAt(i)) & 0x7fffffff;
    }
    return WaPalette
        .avatarPalette[hash % WaPalette.avatarPalette.length];
  }

  String get _initial {
    final trimmed = widget.name.trim();
    if (trimmed.isEmpty) return '?';
    for (final rune in trimmed.runes) {
      final char = String.fromCharCode(rune);
      if (char.trim().isNotEmpty) return char.toUpperCase();
    }
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
      child: Text(
        _initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: widget.size * 0.42,
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    return ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: FutureBuilder<Uint8List?>(
          future: _image,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null || bytes.isEmpty) return fallback;
            return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
          },
        ),
      ),
    );
  }
}
