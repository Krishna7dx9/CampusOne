import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/allocation_service.dart';

class AllocateRoomDialog extends ConsumerStatefulWidget {
  const AllocateRoomDialog({
    super.key,
    required this.roomId,
    required this.hostelId,
    required this.orgId,
  });
  final String roomId;
  final String hostelId;
  final String orgId;

  @override
  ConsumerState<AllocateRoomDialog> createState() => _AllocateRoomDialogState();
}

class _AllocateRoomDialogState extends ConsumerState<AllocateRoomDialog> {
  final TextEditingController _studentId = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _studentId.dispose();
    super.dispose();
  }

  Future<void> _allocate() async {
    if (_studentId.text.trim().isEmpty) {
      setState(() => _error = 'Student ID required');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await AllocationService().allocate(
        orgId: widget.orgId,
        studentId: _studentId.text.trim(),
        roomId: widget.roomId,
        hostelId: widget.hostelId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Allocate Room'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _studentId,
            decoration: const InputDecoration(labelText: 'Student ID'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _allocate,
          child: const Text('Allocate'),
        ),
      ],
    );
  }
}
