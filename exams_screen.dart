import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../models/exam.dart';
import '../../services/exam_service.dart';

class ExamsScreen extends ConsumerStatefulWidget {
  const ExamsScreen({super.key});

  @override
  ConsumerState<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends ConsumerState<ExamsScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _term = TextEditingController();
  bool _submitting = false;
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _term.dispose();
    super.dispose();
  }

  Future<void> _createExam() async {
    if (!_formKey.currentState!.validate()) return;
    final org = ref.read(currentOrgProvider).value;
    if (org == null) return;
    setState(() => _submitting = true);
    try {
      final orgId = org['id'] ?? org['orgId'];
      final exam = Exam(
        id: '',
        orgId: orgId,
        name: _name.text.trim(),
        term: _term.text.trim(),
        schedule: const <String, DateTime>{},
        published: false,
      );
      await ExamService().createExam(exam);
      if (mounted) {
        _name.clear();
        _term.clear();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final org = ref.watch(currentOrgProvider).value;
    final orgId = org != null ? (org['id'] ?? org['orgId']) : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exams'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).maybePop();
            } else {
              Navigator.of(context).pushReplacementNamed('/');
            }
          },
        ),
      ),
      body: orgId == null
          ? const Center(child: Text('Organization not loaded'))
          : LayoutBuilder(
              builder: (context, c) {
                final bool narrow = c.maxWidth < 900;
                Widget createForm = Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Create Exam',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _name,
                              decoration: const InputDecoration(
                                labelText: 'Name',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _term,
                              decoration: const InputDecoration(
                                labelText: 'Term',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _submitting ? null : _createExam,
                                child: _submitting
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Create'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );

                Widget list = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: SizedBox(
                        height: 40,
                        child: TextField(
                          controller: _search,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Search exams by name or term',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                    Expanded(child: _ExamsList(orgId: orgId, query: _search.text.trim())),
                  ],
                );

                if (narrow) {
                  return ListView(
                    children: [createForm, const SizedBox(height: 8), list],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 1, child: createForm),
                    const VerticalDivider(width: 1),
                    Expanded(flex: 2, child: list),
                  ],
                );
              },
            ),
    );
  }
}

class _ExamsList extends StatelessWidget {
  const _ExamsList({required this.orgId, this.query = ''});
  final String orgId;
  final String query;

  @override
  Widget build(BuildContext context) {
    final qRef = FirebaseFirestore.instance
        .collection('exams')
        .where('orgId', isEqualTo: orgId);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: qRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Failed to load exams'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        var docs = snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        // Sort client-side by name to avoid composite index requirement.
        docs.sort((a, b) {
          final an = (a.data()['name'] as String? ?? '').toLowerCase();
          final bn = (b.data()['name'] as String? ?? '').toLowerCase();
          return an.compareTo(bn);
        });
        if (this.query.isNotEmpty) {
          final q = this.query.toLowerCase();
          docs = docs.where((d) {
            final n = (d.data()['name'] as String? ?? '').toLowerCase();
            final t = (d.data()['term'] as String? ?? '').toLowerCase();
            return n.contains(q) || t.contains(q);
          }).toList(growable: false);
        }
        if (docs.isEmpty) {
          return const Center(child: Text('No exams'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final e = Exam.fromFirestore(docs[index]);
            final Color chipBg = Theme.of(context).colorScheme.surfaceVariant;
            final Color chipFg = Theme.of(context).colorScheme.primary;
            return Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _chip('Term: ${e.term}', chipBg, chipFg),
                              _chip(e.published ? 'Published' : 'Draft', chipBg, e.published ? Colors.green : chipFg),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        IconButton(
                          tooltip: e.published ? 'Unpublish' : 'Publish',
                          icon: Icon(e.published ? Icons.visibility_off : Icons.visibility),
                          onPressed: () async {
                            await ExamService().setPublished(e.id, !e.published);
                          },
                        ),
                        IconButton(
                          tooltip: 'Set sample schedule',
                          icon: const Icon(Icons.event_note),
                          onPressed: () async {
                            final tomorrow = DateTime.now().add(const Duration(days: 1));
                            final schedule = <String, dynamic>{
                              'CLASS-A': Timestamp.fromDate(
                                DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10),
                              ),
                            };
                            await ExamService().updateSchedule(e.id, schedule: schedule);
                          },
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
  }
}

Widget _chip(String label, Color bg, Color fg) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
  );
}


