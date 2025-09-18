import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import '../../core/app_providers.dart';
import '../../models/student.dart';
import '../../services/student_service.dart';
import 'add_student_screen.dart';
import 'admin_dashboard_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StudentsListScreen extends ConsumerStatefulWidget {
  final String? initialSearch;
  const StudentsListScreen({super.key, this.initialSearch});

  @override
  ConsumerState<StudentsListScreen> createState() => _StudentsListScreenState();
}

class _StudentsListScreenState extends ConsumerState<StudentsListScreen> {
  String _dept = '';
  String _year = '';
  String _status = '';
  String _search = '';
  Timer? _debounce;

  late final TextEditingController _searchController;

  // Sorting handled server-side for paged mode; keep placeholders if needed later
  // int _sortColumnIndex = 0;
  // bool _sortAscending = true;

  int _rowsPerPage = 10;
  int _page = 0;

  final Set<String> _selectedIds = <String>{};
  List<String> _visibleIds = const <String>[];

  // Paged data state
  final Map<int, List<Student>> _pageData = <int, List<Student>>{};
  final Map<int, DocumentSnapshot<Map<String, dynamic>>?> _pageCursor =
      <int, DocumentSnapshot<Map<String, dynamic>>?>{};
  bool _loading = false;

  List<int> _visiblePageButtons(int totalItems) {
    final maxPage = (totalItems == 0) ? 0 : ((totalItems - 1) ~/ _rowsPerPage);
    final current = _page;
    final pages = <int>{0, maxPage};
    for (int i = current - 2; i <= current + 2; i++) {
      if (i >= 0 && i <= maxPage) pages.add(i);
    }
    final sorted = pages.toList()..sort();
    return sorted;
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (reset) {
      _pageData.clear();
      _pageCursor.clear();
      _page = 0;
    }
    final org = ref.read(currentOrgProvider).value;
    final String? orgId = org != null ? (org['id'] ?? org['orgId']) : null;
    if (orgId == null) return;
    if (_pageData.containsKey(_page)) return; // cached
    setState(() => _loading = true);

    DocumentSnapshot<Map<String, dynamic>>? startAfter;
    if (_page > 0) startAfter = _pageCursor[_page - 1];

    final (students, lastDoc) = await StudentService().fetchStudentsPage(
      orgId: orgId,
      dept: _dept.isEmpty ? null : _dept,
      year: _year.isEmpty ? null : _year,
      status: _status.isEmpty ? null : _status,
      namePrefix: _search.isEmpty ? null : _search,
      limit: _rowsPerPage,
      startAfter: startAfter,
    );
    _pageData[_page] = students;
    _pageCursor[_page] = lastDoc;

    // Prefetch next page cursor (without storing data yet) for snappy next
    if (lastDoc != null) {
      _pageCursor[_page] = lastDoc;
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  void initState() {
    super.initState();
    _search = (widget.initialSearch ?? '').trim().toLowerCase();
    _searchController = TextEditingController(text: widget.initialSearch ?? '');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _resetPaging() {
    _page = 0;
    _pageData.clear();
    _pageCursor.clear();
    setState(() {});
    _loadPage(reset: true);
  }

  void _setSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _search = v.trim().toLowerCase();
      _resetPaging();
    });
  }

  Future<void> _bulkDelete(List<Student> allData) async {
    if (_selectedIds.isEmpty) return;
    final toDelete = allData.where((s) => _selectedIds.contains(s.id)).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete selected?'),
        content: Text('This will delete ${toDelete.length} students.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        for (final s in toDelete) {
          await StudentService().deleteStudent(s.id);
        }
        // Remove from local caches
        for (final entry in _pageData.entries) {
          entry.value.removeWhere((e) => _selectedIds.contains(e.id));
        }
        // If current page is empty after deletions, move back a page if possible
        if ((_pageData[_page]?.isEmpty ?? true) && _page > 0) {
          _page -= 1;
        }
        _clearSelection();
        if (mounted) {
          setState(() {});
          // Ensure page is filled
          await _loadPage();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Deleted ${toDelete.length} students')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
        }
      }
    }
  }

  Future<void> _bulkExport(List<Student> allData) async {
    if (_selectedIds.isEmpty) return;
    final rows = allData.where((s) => _selectedIds.contains(s.id)).toList();
    await _exportCsv(rows);
  }

  void _applyVisibleIds(List<Student> visible) {
    _visibleIds = visible.map((e) => e.id).toList(growable: false);
  }

  void _toggleSelect(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  void _toggleSelectAllVisible(bool selectAll) {
    setState(() {
      if (selectAll) {
        _selectedIds.addAll(_visibleIds);
      } else {
        _selectedIds.removeAll(_visibleIds);
      }
    });
  }

  void _clearSelection() => setState(() => _selectedIds.clear());

  Future<void> _exportCsv(List<Student> visibleStudents) async {
    final headers = ['Roll No', 'Name', 'Department', 'Year', 'Status'];
    final rows = visibleStudents
        .map((s) => [s.enrollNo, s.name, s.dept, s.year, s.status])
        .toList();
    final csv = StringBuffer()..writeln(headers.join(','));
    for (final r in rows) {
      csv.writeln(
        r.map((v) => '"${v.toString().replaceAll('"', '""')}"').join(','),
      );
    }
    if (kIsWeb) {
      final bytes = utf8.encode(csv.toString());
      final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final a = html.AnchorElement(href: url)..download = 'students.csv';
      a.click();
      html.Url.revokeObjectUrl(url);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV export supported on web for now')),
      );
    }
  }

  List<Student>? _lastData;

  @override
  Widget build(BuildContext context) {
    final org = ref.watch(currentOrgProvider).value;
    final orgId = org != null ? (org['id'] ?? org['orgId']) : null;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            final didPop = await Navigator.maybePop(context);
            if (!didPop && mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
              );
            }
          },
        ),
        title: const Text('Student Management'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Bulk Actions',
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            offset: const Offset(0, 12),
            onSelected: (value) async {
              switch (value) {
                case 'export':
                  await _bulkExport(_lastData ?? const <Student>[]);
                  break;
                case 'delete':
                  await _bulkDelete(_lastData ?? const <Student>[]);
                  break;
                case 'select_all':
                  _toggleSelectAllVisible(true);
                  break;
                case 'clear':
                  _clearSelection();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'export',
                enabled: _selectedIds.isNotEmpty,
                child: Row(
                  children: [
                    const Icon(Icons.download_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text('Export selected (${_selectedIds.length})'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                enabled: _selectedIds.isNotEmpty,
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline, size: 18),
                    const SizedBox(width: 8),
                    Text('Delete selected (${_selectedIds.length})'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'select_all',
                child: Row(
                  children: [
                    Icon(Icons.select_all, size: 18),
                    SizedBox(width: 8),
                    Text('Select all on page'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'clear',
                enabled: _selectedIds.isNotEmpty,
                child: Row(
                  children: const [
                    Icon(Icons.clear_all, size: 18),
                    SizedBox(width: 8),
                    Text('Clear selection'),
                  ],
                ),
              ),
            ],
            child: Builder(
              builder: (context) {
                final Color border = Theme.of(context).dividerColor;
                final Color bg = Theme.of(context).colorScheme.surface;
                final TextStyle? ts = Theme.of(context).textTheme.labelLarge;
                return Container(
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: border),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.playlist_add_check_circle_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text('Bulk actions', style: ts),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          if (_selectedIds.isNotEmpty) ...[
            OutlinedButton.icon(
              onPressed: () => _bulkExport(_lastData ?? const <Student>[]),
              icon: const Icon(Icons.download_outlined),
              label: Text('Export (${_selectedIds.length})'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _bulkDelete(_lastData ?? const <Student>[]),
              icon: const Icon(Icons.delete_outline),
              label: Text('Delete (${_selectedIds.length})'),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton.icon(
            onPressed: () async {
              final created = await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddStudentScreen()),
              );
              if (created == true) {
                _resetPaging();
              }
            },
            icon: const Icon(Icons.person_add),
            label: const Text('Add Student'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: orgId == null
          ? const Center(child: Text('Organization not loaded'))
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: IconButton(
                              tooltip: 'Search',
                              icon: const Icon(Icons.arrow_forward),
                              onPressed: () =>
                                  _setSearch(_searchController.text),
                            ),
                            hintText: 'Search by name, roll no, etc.',
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: _setSearch,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 220,
                        child: StreamBuilder<List<String>>(
                          stream: StudentService().streamDepartments(orgId),
                          builder: (context, snap) {
                            final items = <DropdownMenuItem<String>>[
                              const DropdownMenuItem(
                                value: '',
                                child: Text('All Departments'),
                              ),
                              ...[...(snap.data ?? const <String>[])].map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              ),
                            ];
                            return DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _dept.isEmpty ? null : _dept,
                              decoration: const InputDecoration(
                                labelText: 'Department',
                                border: OutlineInputBorder(),
                              ),
                              items: items,
                              onChanged: (v) {
                                _dept = (v ?? '');
                                _resetPaging();
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 180,
                        child: StreamBuilder<List<String>>(
                          stream: StudentService().streamYears(orgId),
                          builder: (context, snap) {
                            final items = <DropdownMenuItem<String>>[
                              const DropdownMenuItem(
                                value: '',
                                child: Text('All Years'),
                              ),
                              ...[...(snap.data ?? const <String>[])].map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              ),
                            ];
                            return DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _year.isEmpty ? null : _year,
                              decoration: const InputDecoration(
                                labelText: 'Year',
                                border: OutlineInputBorder(),
                              ),
                              items: items,
                              onChanged: (v) {
                                _year = (v ?? '');
                                _resetPaging();
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 160,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _status.isEmpty ? null : _status,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: '',
                              child: Text('Any Status'),
                            ),
                            DropdownMenuItem(
                              value: 'active',
                              child: Text('Active'),
                            ),
                            DropdownMenuItem(
                              value: 'alumni',
                              child: Text('Alumni'),
                            ),
                            DropdownMenuItem(
                              value: 'suspended',
                              child: Text('Inactive'),
                            ),
                          ],
                          onChanged: (v) {
                            _status = v ?? '';
                            _resetPaging();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (_dept.isNotEmpty)
                          InputChip(
                            label: Text('Dept: $_dept'),
                            onDeleted: () {
                              _dept = '';
                              _resetPaging();
                            },
                          ),
                        if (_year.isNotEmpty)
                          InputChip(
                            label: Text('Year: $_year'),
                            onDeleted: () {
                              _year = '';
                              _resetPaging();
                            },
                          ),
                        if (_status.isNotEmpty)
                          InputChip(
                            label: Text('Status: $_status'),
                            onDeleted: () {
                              _status = '';
                              _resetPaging();
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: FutureBuilder<void>(
                      future: _loadPage(),
                      builder: (context, _) {
                        final data = _pageData[_page] ?? const <Student>[];
                        _lastData = data;
                        final visible = data; // already page-sized
                        _applyVisibleIds(visible);
                        if (data.isEmpty) {
                          if (_loading) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return const Center(child: Text('No students'));
                        }
                        return Column(
                          children: [
                            Expanded(
                              child: Card(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Column(
                                    children: [
                                      Container(
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                        child: Row(
                                          children: [
                                            Text(
                                              'Showing ${visible.length} of ${data.length} students',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.labelLarge,
                                            ),
                                            const Spacer(),
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _exportCsv(visible),
                                              icon: const Icon(
                                                Icons.download_outlined,
                                              ),
                                              label: const Text(
                                                'Export current page',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              minWidth: 900,
                                            ),
                                            child: SingleChildScrollView(
                                              child: DataTable(
                                                checkboxHorizontalMargin: 12,
                                                showCheckboxColumn: true,
                                                onSelectAll: (v) =>
                                                    _toggleSelectAllVisible(
                                                      v ?? false,
                                                    ),
                                                // Sorting disabled in paged mode for now; could be added with server-side order
                                                sortColumnIndex: null,
                                                sortAscending: true,
                                                headingRowHeight: 42,
                                                dataRowMinHeight: 56,
                                                dataRowMaxHeight: 64,
                                                columns: [
                                                  DataColumn(
                                                    label: const Text(
                                                      'Roll No',
                                                    ),
                                                    onSort: (i, asc) => setState(
                                                      () {
                                                        // _sortColumnIndex = i;
                                                        // _sortAscending = asc;
                                                      },
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: const Text('Name'),
                                                    onSort: (i, asc) => setState(
                                                      () {
                                                        // _sortColumnIndex = i;
                                                        // _sortAscending = asc;
                                                      },
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: const Text(
                                                      'Department',
                                                    ),
                                                    onSort: (i, asc) => setState(
                                                      () {
                                                        // _sortColumnIndex = i;
                                                        // _sortAscending = asc;
                                                      },
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: const Text('Year'),
                                                    onSort: (i, asc) => setState(
                                                      () {
                                                        // _sortColumnIndex = i;
                                                        // _sortAscending = asc;
                                                      },
                                                    ),
                                                  ),
                                                  const DataColumn(
                                                    label: Text(
                                                      'Contact Details',
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: const Text('Status'),
                                                    onSort: (i, asc) => setState(
                                                      () {
                                                        // _sortColumnIndex = i;
                                                        // _sortAscending = asc;
                                                      },
                                                    ),
                                                  ),
                                                  const DataColumn(
                                                    label: Text('Actions'),
                                                  ),
                                                ],
                                                rows: List.generate(visible.length, (
                                                  idx,
                                                ) {
                                                  final s = visible[idx];
                                                  final selected = _selectedIds
                                                      .contains(s.id);
                                                  final rowColor =
                                                      WidgetStateProperty.resolveWith<
                                                        Color?
                                                      >((states) {
                                                        if (states.contains(
                                                          WidgetState.selected,
                                                        )) {
                                                          return null;
                                                        }
                                                        return idx.isEven
                                                            ? Theme.of(context)
                                                                  .colorScheme
                                                                  .surface
                                                                  .withOpacity(
                                                                    0.02,
                                                                  )
                                                            : null;
                                                      });
                                                  final email =
                                                      (s.contactInfo['email']
                                                          as String?) ??
                                                      '';
                                                  final phone =
                                                      (s.contactInfo['phone']
                                                          as String?) ??
                                                      '';
                                                  return DataRow(
                                                    selected: selected,
                                                    onSelectChanged: (v) =>
                                                        _toggleSelect(
                                                          s.id,
                                                          v ?? false,
                                                        ),
                                                    color: rowColor,
                                                    cells: [
                                                      DataCell(
                                                        Text(s.enrollNo),
                                                      ),
                                                      DataCell(
                                                        Row(
                                                          children: [
                                                            CircleAvatar(
                                                              radius: 12,
                                                              child: Builder(
                                                                builder: (_) {
                                                                  final String
                                                                  trimmed = s
                                                                      .name
                                                                      .trim();
                                                                  if (trimmed
                                                                      .isEmpty) {
                                                                    return const Text(
                                                                      'S',
                                                                      style: TextStyle(
                                                                        fontSize:
                                                                            11,
                                                                      ),
                                                                    );
                                                                  }
                                                                  final int
                                                                  end =
                                                                      trimmed.length >=
                                                                          2
                                                                      ? 2
                                                                      : trimmed
                                                                            .length;
                                                                  final String
                                                                  initials = trimmed
                                                                      .substring(
                                                                        0,
                                                                        end,
                                                                      )
                                                                      .toUpperCase();
                                                                  return Text(
                                                                    initials,
                                                                    style: const TextStyle(
                                                                      fontSize:
                                                                          11,
                                                                    ),
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Flexible(
                                                              child: Text(
                                                                s.name,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      DataCell(Text(s.dept)),
                                                      DataCell(Text(s.year)),
                                                      DataCell(
                                                        Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Text(email),
                                                            Text(
                                                              phone,
                                                              style: Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                    color: Theme.of(
                                                                      context,
                                                                    ).hintColor,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      DataCell(
                                                        _StatusPill(
                                                          status: s.status,
                                                        ),
                                                      ),
                                                      DataCell(
                                                        Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            _ActionIcon(
                                                              tooltip: 'View',
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .primary,
                                                              icon: Icons
                                                                  .visibility_outlined,
                                                              onTap: () async {
                                                                await Navigator.of(
                                                                  context,
                                                                ).push(
                                                                  MaterialPageRoute(
                                                                    builder: (_) =>
                                                                        StudentDetailScreen(
                                                                          student:
                                                                              s,
                                                                        ),
                                                                  ),
                                                                );
                                                              },
                                                            ),
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            _ActionIcon(
                                                              tooltip: 'Edit',
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .tertiary,
                                                              icon: Icons
                                                                  .edit_outlined,
                                                              onTap: () async {
                                                                final changed =
                                                                    await Navigator.of(
                                                                      context,
                                                                    ).push(
                                                                      MaterialPageRoute(
                                                                        builder: (_) => AddStudentScreen(
                                                                          student:
                                                                              s,
                                                                        ),
                                                                      ),
                                                                    );
                                                                if (changed ==
                                                                    true) {
                                                                  _resetPaging();
                                                                }
                                                              },
                                                            ),
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            _ActionIcon(
                                                              tooltip: 'Delete',
                                                              color: Theme.of(
                                                                context,
                                                              ).colorScheme.error,
                                                              icon: Icons
                                                                  .delete_outline,
                                                              onTap: () async {
                                                                final ok = await showDialog<bool>(
                                                                  context:
                                                                      context,
                                                                  builder: (ctx) => AlertDialog(
                                                                    title: const Text(
                                                                      'Delete student?',
                                                                    ),
                                                                    content: Text(
                                                                      'This will permanently delete ${s.name}.',
                                                                    ),
                                                                    actions: [
                                                                      TextButton(
                                                                        onPressed: () =>
                                                                            Navigator.of(
                                                                              ctx,
                                                                            ).pop(
                                                                              false,
                                                                            ),
                                                                        child: const Text(
                                                                          'Cancel',
                                                                        ),
                                                                      ),
                                                                      FilledButton(
                                                                        onPressed: () =>
                                                                            Navigator.of(
                                                                              ctx,
                                                                            ).pop(
                                                                              true,
                                                                            ),
                                                                        child: const Text(
                                                                          'Delete',
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                );
                                                                if (ok ==
                                                                    true) {
                                                                  try {
                                                                    await StudentService()
                                                                        .deleteStudent(
                                                                          s.id,
                                                                        );
                                                                    // Update caches
                                                                    _pageData[_page]
                                                                        ?.removeWhere(
                                                                          (e) =>
                                                                              e.id ==
                                                                              s.id,
                                                                        );
                                                                    // If page empty, step back if possible and ensure data
                                                                    if ((_pageData[_page]?.isEmpty ??
                                                                            true) &&
                                                                        _page >
                                                                            0) {
                                                                      _page -=
                                                                          1;
                                                                    }
                                                                    if (mounted) {
                                                                      setState(
                                                                        () {},
                                                                      );
                                                                      await _loadPage();
                                                                      ScaffoldMessenger.of(
                                                                        context,
                                                                      ).showSnackBar(
                                                                        SnackBar(
                                                                          content: Text(
                                                                            'Deleted ${s.name}',
                                                                          ),
                                                                        ),
                                                                      );
                                                                    }
                                                                  } catch (e) {
                                                                    if (mounted) {
                                                                      ScaffoldMessenger.of(
                                                                        context,
                                                                      ).showSnackBar(
                                                                        SnackBar(
                                                                          content: Text(
                                                                            'Failed to delete: $e',
                                                                          ),
                                                                        ),
                                                                      );
                                                                    }
                                                                  }
                                                                }
                                                              },
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                }),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Text('Rows per page: '),
                                    const SizedBox(width: 4),
                                    DropdownButton<int>(
                                      value: _rowsPerPage,
                                      items: const [10, 20, 50]
                                          .map(
                                            (e) => DropdownMenuItem(
                                              value: e,
                                              child: Text('$e'),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) {
                                        if (v == null) return;
                                        setState(() {
                                          _rowsPerPage = v;
                                          _page = 0;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    OutlinedButton(
                                      onPressed: _page > 0
                                          ? () => setState(() {
                                              _page = 0;
                                              _loadPage();
                                            })
                                          : null,
                                      child: const Text('«'),
                                    ),
                                    IconButton(
                                      tooltip: 'Previous',
                                      onPressed: _page > 0
                                          ? () => setState(() {
                                              _page -= 1;
                                              _loadPage();
                                            })
                                          : null,
                                      icon: const Icon(Icons.chevron_left),
                                    ),
                                    Builder(
                                      builder: (context) {
                                        final total =
                                            (_pageData[_page]?.length ?? 0) +
                                            (_page * _rowsPerPage);
                                        final buttons = _visiblePageButtons(
                                          total,
                                        );
                                        Widget gap() => const Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          child: Text('…'),
                                        );
                                        final widgets = <Widget>[];
                                        for (
                                          int i = 0;
                                          i < buttons.length;
                                          i++
                                        ) {
                                          final p = buttons[i];
                                          if (i > 0 &&
                                              buttons[i] !=
                                                  buttons[i - 1] + 1) {
                                            widgets.add(gap());
                                          }
                                          widgets.add(
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 2,
                                                  ),
                                              child: OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  backgroundColor: p == _page
                                                      ? Theme.of(context)
                                                            .colorScheme
                                                            .primary
                                                            .withOpacity(0.08)
                                                      : null,
                                                ),
                                                onPressed: () => setState(() {
                                                  _page = p;
                                                  _loadPage();
                                                }),
                                                child: Text('${p + 1}'),
                                              ),
                                            ),
                                          );
                                        }
                                        return Row(children: widgets);
                                      },
                                    ),
                                    IconButton(
                                      tooltip: 'Next',
                                      onPressed: (_pageCursor[_page] != null)
                                          ? () => setState(() {
                                              _page += 1;
                                              _loadPage();
                                            })
                                          : null,
                                      icon: const Icon(Icons.chevron_right),
                                    ),
                                    OutlinedButton(
                                      onPressed: (_pageCursor[_page] != null)
                                          ? () => setState(() {
                                              // jump ahead one page until no cursor; simple approximation
                                              _page += 1;
                                              _loadPage();
                                            })
                                          : null,
                                      child: const Text('»'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  Color _color(BuildContext context) {
    switch (status) {
      case 'active':
        return Colors.green.shade600;
      case 'alumni':
        return Colors.blueGrey;
      case 'suspended':
        return Colors.orange.shade700;
      default:
        return Theme.of(context).hintColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(0.32)),
      ),
      child: Text(
        status == 'suspended' ? 'Inactive' : status,
        style: TextStyle(color: c, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color foreground = color;
    final Color background = color.withOpacity(0.10);
    final Color border = color.withOpacity(0.20);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: foreground),
        ),
      ),
    );
  }
}

class StudentDetailScreen extends StatelessWidget {
  const StudentDetailScreen({super.key, required this.student});
  final Student student;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(student.name)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        _InfoTile(title: 'Enrollment', value: student.enrollNo),
                        _InfoTile(title: 'Department', value: student.dept),
                        _InfoTile(title: 'Year', value: student.year),
                        _InfoTile(title: 'Status', value: student.status),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Contact',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(student.contactInfo.toString()),
                    const SizedBox(height: 16),
                    Text(
                      'Academic',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(student.academicInfo.toString()),
                    const SizedBox(height: 16),
                    Text(
                      'Custom',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(student.custom.toString()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String title;
  final String value;
  const _InfoTile({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: Theme.of(context).hintColor),
        ),
        subtitle: Text(value, style: Theme.of(context).textTheme.titleSmall),
      ),
    );
  }
}
