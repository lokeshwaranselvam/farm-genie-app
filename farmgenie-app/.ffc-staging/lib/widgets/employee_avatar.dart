import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/farmgenie_api.dart';

class EmployeeAvatar extends StatefulWidget {
  const EmployeeAvatar({
    super.key,
    required this.name,
    this.image,
    this.radius = 44,
  });
  final String name;
  final String? image;
  final double radius;
  @override
  State<EmployeeAvatar> createState() => _EmployeeAvatarState();
}

class _EmployeeAvatarState extends State<EmployeeAvatar> {
  Future<Uint8List?>? _photo;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant EmployeeAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image || oldWidget.name != widget.name)
      _load();
  }

  void _load() {
    final path = widget.image?.trim() ?? '';
    _photo = path.isEmpty ? null : FarmgenieApi.employeePhoto(path);
  }

  Widget _fallback() => ColoredBox(
    color: const Color(0xFFEAF9F1),
    child: Center(
      child: Text(
        widget.name.trim().isEmpty ? 'E' : widget.name.trim()[0].toUpperCase(),
        style: TextStyle(
          fontSize: widget.radius * .8,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF008C58),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Semantics(
    label: '${widget.name} profile picture',
    image: true,
    child: ClipOval(
      child: SizedBox(
        width: widget.radius * 2,
        height: widget.radius * 2,
        child: FutureBuilder<Uint8List?>(
          future: _photo,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting)
              return const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            if (snapshot.data == null) return _fallback();
            return Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) => _fallback(),
            );
          },
        ),
      ),
    ),
  );
}
