import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../models/room.dart';
import '../../services/room_service.dart';
import 'allocate_room_dialog.dart';
import '../../widgets/erp_search_bar.dart';

class RoomsGridScreen extends ConsumerStatefulWidget {
  const RoomsGridScreen({super.key});

  @override
  ConsumerState<RoomsGridScreen> createState() => _RoomsGridScreenState();
}

class _RoomsGridScreenState extends ConsumerState<RoomsGridScreen> {
  // Single-hostel simplification: remove hostel filter
  String _status = '';
  final TextEditingController _search = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final org = ref.watch(currentOrgProvider).value;
    final orgId = org != null ? (org['id'] ?? org['orgId']) : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rooms'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).maybePop();
            } else {
              Navigator.of(context).pushReplacementNamed('/');
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Add room',
            icon: const Icon(Icons.add),
            onPressed: orgId == null
                ? null
                : () async {
                    await showDialog(
                      context: context,
                      builder: (context) {
                        final numberCtrl = TextEditingController();
                        final capacityCtrl = TextEditingController(text: '2');
                        final hostelCtrl = TextEditingController(text: 'H1');
                        String status = 'available';
                        bool submitting = false;
                        String? error;
                        return StatefulBuilder(
                          builder: (context, setStateDialog) {
                            Future<void> onSave() async {
                              final number = numberCtrl.text.trim();
                              final hostel = hostelCtrl.text.trim();
                              final cap = int.tryParse(capacityCtrl.text.trim()) ?? 0;
                              if (number.isEmpty || hostel.isEmpty || cap <= 0) {
                                setStateDialog(() => error = 'All fields required (capacity > 0)');
                                return;
                              }
                              setStateDialog(() { submitting = true; error = null; });
                              try {
                                await RoomService().createRoom(
                                  orgId: orgId,
                                  hostelId: hostel,
                                  number: number,
                                  capacity: cap,
                                  status: status,
                                );
                                if (mounted) Navigator.pop(context);
                              } catch (e) {
                                setStateDialog(() => error = e.toString());
                              } finally {
                                setStateDialog(() => submitting = false);
                              }
                            }

                            return AlertDialog(
                              title: const Text('Add Room'),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextField(controller: numberCtrl, decoration: const InputDecoration(labelText: 'Room number')),
                                    TextField(controller: hostelCtrl, decoration: const InputDecoration(labelText: 'Hostel ID')),
                                    TextField(controller: capacityCtrl, decoration: const InputDecoration(labelText: 'Capacity'), keyboardType: TextInputType.number),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      initialValue: status,
                                      items: const [
                                        DropdownMenuItem(value: 'available', child: Text('Available')),
                                        DropdownMenuItem(value: 'full', child: Text('Full')),
                                        DropdownMenuItem(value: 'maintenance', child: Text('Maintenance')),
                                      ],
                                      onChanged: (v) => setStateDialog(() => status = v ?? 'available'),
                                      decoration: const InputDecoration(labelText: 'Status'),
                                    ),
                                    if (error != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(error!, style: const TextStyle(color: Colors.red)),
                                      ),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                FilledButton(onPressed: submitting ? null : onSave, child: const Text('Save')),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
          ),
        ],
      ),
      body: orgId == null
          ? const Center(child: Text('Organization not loaded'))
          : Column(
              children: [
                // Filters + search
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Row(
                    children: [
                      // Single-hostel: remove hostel selector; leave an empty space for balance on wide screens
                      const SizedBox(width: 0),
                      const SizedBox(width: 8),
                      // Status quick chips (ERP-style, same height as search)
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Theme.of(context).dividerColor),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  ChoiceChip(
                                    label: const Text('Any'),
                                    selected: _status.isEmpty,
                                    onSelected: (_) => setState(() => _status = ''),
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: const Text('Available'),
                                    selected: _status == 'available',
                                    onSelected: (_) => setState(() => _status = 'available'),
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: const Text('Full'),
                                    selected: _status == 'full',
                                    onSelected: (_) => setState(() => _status = 'full'),
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: const Text('Maintenance'),
                                    selected: _status == 'maintenance',
                                    onSelected: (_) => setState(() => _status = 'maintenance'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // ERP-style search bar
                      Expanded(
                        child: ErpSearchBar(
                          controller: _search,
                          hintText: 'Search room number',
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<Room>>(
                    stream: RoomService().streamRooms(
                      orgId: orgId,
                      // Single-hostel: no hostelId filter
                      hostelId: null,
                      status: _status.isEmpty ? null : _status,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Failed to load rooms'),
                              const SizedBox(height: 8),
                              OutlinedButton(onPressed: () => setState(() {}), child: const Text('Retry')),
                            ],
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      var rooms = snapshot.data!;
                      final q = _search.text.trim().toLowerCase();
                      if (q.isNotEmpty) {
                        rooms = rooms
                            .where((r) => r.number.toLowerCase().contains(q))
                            .toList();
                      }
                      // Deduplicate rooms by logical key (hostelId + number) in case the backend contains duplicate docs
                      if (rooms.isNotEmpty) {
                        final Set<String> seen = <String>{};
                        rooms = rooms.where((r) {
                          final key = '${r.hostelId}::${r.number}'.toLowerCase();
                          if (seen.contains(key)) return false;
                          seen.add(key);
                          return true;
                        }).toList();
                      }
                      // Stable ordering: hostelId ASC, then numeric room number ASC, then number string ASC
                      if (rooms.isNotEmpty) {
                        int _num(String s) {
                          final m = RegExp(r'\d+').firstMatch(s);
                          return int.tryParse(m?.group(0) ?? '') ?? 0;
                        }
                        rooms.sort((a, b) {
                          final byHostel = a.hostelId.compareTo(b.hostelId);
                          if (byHostel != 0) return byHostel;
                          final byNum = _num(a.number).compareTo(_num(b.number));
                          if (byNum != 0) return byNum;
                          return a.number.compareTo(b.number);
                        });
                      }
                      if (rooms.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('No rooms found'),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: orgId == null
                                    ? null
                                    : () => ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Use + to add a room')),
                                        ),
                                icon: const Icon(Icons.add),
                                label: const Text('Add your first room'),
                              ),
                            ],
                          ),
                        );
                      }
                      return LayoutBuilder(
                        builder: (context, c) {
                          // Responsive grid count
                          final width = c.maxWidth;
                          int cross = 1;
                          if (width >= 1200) cross = 3;
                          else if (width >= 800) cross = 2;

                          return GridView.builder(
                            key: const PageStorageKey('roomsGrid'),
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: cross,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 1.9,
                                ),
                            itemCount: rooms.length,
                            itemBuilder: (context, index) {
                              final r = rooms[index];
                              final isFull = r.occupancy >= r.capacity;
                              final double ratio = r.capacity == 0
                                  ? 0
                                  : (r.occupancy / r.capacity).clamp(0.0, 1.0);

                              // If not maintenance, compute status from occupancy/capacity
                              final String displayStatus =
                                  r.status == 'maintenance'
                                      ? 'maintenance'
                                      : (isFull ? 'full' : 'available');

                              Color statusColor() {
                                switch (displayStatus) {
                                  case 'available':
                                    return Colors.green.shade600;
                                  case 'full':
                                    return Colors.orange.shade700;
                                  case 'maintenance':
                                  default:
                                    return Colors.grey.shade700;
                                }
                              }

                              return Card(
                                key: ValueKey('room-${r.hostelId}-${r.number}-${r.id}'),
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Room ${r.number}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(fontWeight: FontWeight.w600),
                                          ),
                                          const Spacer(),
                                          // Status chip (derived)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: statusColor().withOpacity(.12),
                                              borderRadius: BorderRadius.circular(999),
                                              border: Border.all(
                                                color: statusColor().withOpacity(.3),
                                              ),
                                            ),
                                            child: Text(
                                              displayStatus,
                                              style: TextStyle(
                                                color: statusColor(),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          // Single-hostel: hide hostel pill
                                          _Pill(icon: Icons.people_outline, label: 'Cap ${r.capacity}'),
                                          _Pill(icon: Icons.person, label: 'Occ ${r.occupancy}'),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      // Occupancy bar
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: LinearProgressIndicator(
                                          minHeight: 8,
                                          value: ratio,
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withOpacity(.4),
                                          color: isFull
                                              ? Colors.orange.shade700
                                              : Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                      const Spacer(),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: () async {
                                              final newStatus =
                                                  r.status == 'maintenance' ? 'available' : 'maintenance';
                                              await RoomService()
                                                  .updateRoom(r.id, {'status': newStatus});
                                            },
                                            icon: const Icon(Icons.build_outlined, size: 18),
                                            label: const Text('Toggle'),
                                          ),
                                          const SizedBox(width: 8),
                                          FilledButton.icon(
                                            onPressed: isFull
                                                ? null
                                                : () async {
                                                    final allocated = await showDialog<bool>(
                                                      context: context,
                                                      builder: (_) => AllocateRoomDialog(
                                                        roomId: r.id,
                                                        hostelId: r.hostelId,
                                                        orgId: orgId,
                                                      ),
                                                    );
                                                    if (allocated == true) setState(() {});
                                                  },
                                            icon: const Icon(Icons.meeting_room_outlined, size: 18),
                                            label: const Text('Allocate'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Color fg = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: fg.withOpacity(.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
