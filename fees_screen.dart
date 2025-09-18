import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/app_providers.dart';
import '../../core/custom_fields.dart';
import '../../models/fee.dart';
import '../../models/student.dart';
import '../../services/fee_service.dart';

class FeesScreen extends ConsumerStatefulWidget {
  const FeesScreen({super.key});

  @override
  ConsumerState<FeesScreen> createState() => _FeesScreenState();
}

class _FeesScreenState extends ConsumerState<FeesScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _studentId = TextEditingController();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _semester = TextEditingController();
  final TextEditingController _enrollNo = TextEditingController();
  Student? _lookedUpStudent;
  DateTime? _dueDate;
  bool _submitting = false;
  String _tab = 'pending';
  final TextEditingController _receiptUrl = TextEditingController();
  Map<String, dynamic> _customValues = {};

  String _formatCurrency(num amount) {
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return formatter.format(amount);
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '-';
    return DateFormat('dd MMM yyyy').format(dt.toLocal());
  }

  @override
  void dispose() {
    _enrollNo.dispose();
    _studentId.dispose();
    _title.dispose();
    _amount.dispose();
    _semester.dispose();
    _receiptUrl.dispose();
    super.dispose();
  }

  Future<void> _createFee() async {
    if (!_formKey.currentState!.validate()) return;
    final org = ref.read(currentOrgProvider).value;
    if (org == null) return;
    setState(() => _submitting = true);
    try {
      final orgId = org['id'] ?? org['orgId'];
      final fee = Fee(
        id: '',
        orgId: orgId,
        studentId: _studentId.text.trim(),
        title: _title.text.trim(),
        amount: num.tryParse(_amount.text.trim()) ?? 0,
        dueDate: _dueDate,
        semester: _semester.text.trim(),
        status: 'pending',
        custom: _customValues,
        createdAt: DateTime.now(),
      );
      await FeeService().createFee(fee);
      if (mounted) {
        _studentId.clear();
        _title.clear();
        _amount.clear();
        _semester.clear();
        setState(() {
          _dueDate = null;
          _customValues = {};
        });
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
        title: const Text('Fees'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).maybePop();
            } else {
              Navigator.of(context).pushReplacementNamed('/');
            }
          },
          tooltip: 'Back',
        ),
      ),
      body: orgId == null
          ? const Center(child: Text('Organization not loaded'))
          : Row(
              children: [
                Expanded(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: ListView(
                        children: [
                          Text(
                            'Create Fee',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          // Base fields rendered dynamically when org provides schema
                          Consumer(builder: (context, ref, _) {
                            final org = ref.watch(currentOrgProvider).value;
                            final baseSchemaRaw = org?['customFields']?['feesBase'];
                            final fields = parseCustomFieldDefinitions(baseSchemaRaw);
                            if (fields.isEmpty) {
                              return Column(children: [
                                // Enrollment number lookup (optional if you want to type studentId directly)
                                TextFormField(
                                  controller: _enrollNo,
                                  decoration: const InputDecoration(labelText: 'Enrollment No'),
                                  textInputAction: TextInputAction.search,
                                  onFieldSubmitted: (_) async {
                                    final orgId = org != null ? (org['id'] ?? org['orgId']) : null;
                                    if (orgId == null) return;
                                    final snap = await FirebaseFirestore.instance
                                        .collection('students')
                                        .where('orgId', isEqualTo: orgId)
                                        .where('enrollNo', isEqualTo: _enrollNo.text.trim())
                                        .limit(1)
                                        .get();
                                    if (snap.docs.isNotEmpty) {
                                      final s = Student.fromFirestore(snap.docs.first);
                                      _studentId.text = s.id;
                                      _title.text = _title.text.isEmpty ? 'Tuition Fee' : _title.text;
                                      _semester.text = _semester.text.isEmpty ? s.year : _semester.text;
                                      setState(() { _lookedUpStudent = s; });
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Student found: ${s.name} (${s.dept})')),
                                      );
                                    } else {
                                      setState(() { _lookedUpStudent = null; });
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('No student found for this enrollment number')),
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(height: 8),
                                if (_lookedUpStudent != null)
                                  Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: const Icon(Icons.person_outline),
                                      title: Text(_lookedUpStudent!.name),
                                      subtitle: Text('Dept: ${_lookedUpStudent!.dept} • Year: ${_lookedUpStudent!.year}'),
                                      trailing: IconButton(
                                        tooltip: 'Clear',
                                        icon: const Icon(Icons.close),
                                        onPressed: () {
                                          setState(() { _lookedUpStudent = null; });
                                        },
                                      ),
                                    ),
                                  ),
                          TextFormField(
                            controller: _studentId,
                                  decoration: const InputDecoration(labelText: 'Student ID'),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _title,
                                  decoration: const InputDecoration(labelText: 'Title'),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _amount,
                                  decoration: const InputDecoration(labelText: 'Amount'),
                            keyboardType: TextInputType.number,
                                  validator: (v) => (num.tryParse(v ?? '') == null) ? 'Enter amount' : null,
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _semester,
                                  decoration: const InputDecoration(labelText: 'Semester'),
                                ),
                              ]);
                            }

                            // Map core controllers to matching keys when provided
                            // Supported keys: studentId,title,amount,semester
                            TextEditingController? controllerFor(String key) {
                              switch (key) {
                                case 'studentId':
                                  return _studentId;
                                case 'title':
                                  return _title;
                                case 'amount':
                                  return _amount;
                                case 'semester':
                                  return _semester;
                                default:
                                  return null;
                              }
                            }

                            return Column(
                              children: [
                                for (final f in fields)
                                  if (f.type == 'enum')
                                    DropdownButtonFormField<String>(
                                      initialValue: null,
                                      items: f.options
                                          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                                          .toList(),
                                      onChanged: (_) {},
                                      decoration: InputDecoration(labelText: f.label + (f.required ? ' *' : '')),
                                    )
                                  else if (f.keyName == 'enrollNo')
                                    TextFormField(
                                      controller: _enrollNo,
                                      decoration: InputDecoration(labelText: (f.label.isEmpty ? 'Enrollment No' : f.label) + (f.required ? ' *' : '')),
                                      textInputAction: TextInputAction.search,
                                      onFieldSubmitted: (_) async {
                                        final orgId = org != null ? (org['id'] ?? org['orgId']) : null;
                                        if (orgId == null) return;
                                        final snap = await FirebaseFirestore.instance
                                            .collection('students')
                                            .where('orgId', isEqualTo: orgId)
                                            .where('enrollNo', isEqualTo: _enrollNo.text.trim())
                                            .limit(1)
                                            .get();
                                        if (snap.docs.isNotEmpty) {
                                          final s = Student.fromFirestore(snap.docs.first);
                                          _studentId.text = s.id;
                                          if (_semester.text.isEmpty) _semester.text = s.year;
                                          setState(() { _lookedUpStudent = s; });
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Student found: ${s.name} (${s.dept})')),
                                          );
                                        } else {
                                          setState(() { _lookedUpStudent = null; });
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('No student found for this enrollment number')),
                                          );
                                        }
                                      },
                                    )
                                  else
                                    TextFormField(
                                      controller: controllerFor(f.keyName) ?? TextEditingController(),
                                      decoration: InputDecoration(labelText: f.label + (f.required ? ' *' : '')),
                                      keyboardType: f.keyName == 'amount' || f.type == 'number'
                                          ? TextInputType.number
                                          : TextInputType.text,
                                      validator: (v) {
                                        if (f.required && (v == null || v.trim().isEmpty)) return 'Required';
                                        if ((f.keyName == 'amount' || f.type == 'number') && num.tryParse(v ?? '') == null) {
                                          return 'Enter number';
                                        }
                                        return null;
                                      },
                                    ),
                                const SizedBox(height: 8),
                              ],
                            );
                          }),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _receiptUrl,
                            decoration: const InputDecoration(
                              labelText: 'Demo receipt URL (optional)',
                              hintText: 'https://.../sample.pdf',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _dueDate == null
                                      ? 'No due date'
                                      : 'Due: ${_dueDate!.toLocal().toString().split(' ').first}',
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  final now = DateTime.now();
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: now,
                                    firstDate: DateTime(now.year - 1),
                                    lastDate: DateTime(now.year + 2),
                                  );
                                  if (picked != null) {
                                    setState(() => _dueDate = picked);
                                  }
                                },
                                child: const Text('Pick due date'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Custom Fields Section
                          Consumer(
                            builder: (context, ref, child) {
                              final org = ref.watch(currentOrgProvider).value;
                              if (org == null) return const SizedBox.shrink();

                              final customFields =
                                  org['customFields']?['fees'] as List?;
                              if (customFields == null ||
                                  customFields.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              final fieldDefinitions =
                                  parseCustomFieldDefinitions(customFields);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Additional Information',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  CustomFieldsForm(
                                    fields: fieldDefinitions,
                                    initialValues: _customValues,
                                    onChanged: (values) {
                                      setState(() {
                                        _customValues = values;
                                      });
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _submitting ? null : _createFee,
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
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('Pending'),
                              selected: _tab == 'pending',
                              onSelected: (_) =>
                                  setState(() => _tab = 'pending'),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Paid'),
                              selected: _tab == 'paid',
                              onSelected: (_) => setState(() => _tab = 'paid'),
                            ),
                            const Spacer(),
                            StreamBuilder<Map<String, num>>(
                              stream: FeeService().streamFeesSummary(orgId),
                              builder: (context, snapshot) {
                                final data =
                                    snapshot.data ??
                                    const <String, num>{
                                      'collected': 0,
                                      'due': 0,
                                    };
                                return Text(
                                  'Collected: ${_formatCurrency(data['collected'] ?? 0)} • Due: ${_formatCurrency(data['due'] ?? 0)}',
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('fees')
                              .where('orgId', isEqualTo: orgId)
                              .where('status', isEqualTo: _tab)
                              .orderBy('dueDate')
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final docs = snapshot.data!.docs;
                            if (docs.isEmpty) {
                              return const Center(child: Text('No records'));
                            }
                            return ListView.separated(
                              itemCount: docs.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final f = Fee.fromFirestore(docs[index]);
                                return ListTile(
                                  title: Text('${f.title} • ${_formatCurrency(f.amount)}'),
                                  subtitle: Text(
                                    'Student: ${f.studentId} • ${f.semester} • Due: ${_formatDate(f.dueDate)}',
                                  ),
                                  trailing: _tab == 'pending'
                                      ? TextButton(
                                          onPressed: () async {
                                            await FeeService().markPaid(
                                              f.id,
                                              paymentDate: DateTime.now(),
                                            );
                                            final url =
                                                _receiptUrl.text
                                                    .trim()
                                                    .isNotEmpty
                                                ? _receiptUrl.text.trim()
                                                : 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf';
                                            await FirebaseFirestore.instance
                                                .collection('fees')
                                                .doc(f.id)
                                                .set({
                                                  'receiptUrl': url,
                                                }, SetOptions(merge: true));
                                          },
                                          child: const Text('Mark paid'),
                                        )
                                      : (f.receiptUrl != null
                                            ? TextButton(
                                                onPressed: () async {
                                                  final url = f.receiptUrl!;
                                                  if (await canLaunchUrlString(
                                                    url,
                                                  )) {
                                                    await launchUrlString(
                                                      url,
                                                      mode: LaunchMode
                                                          .externalApplication,
                                                    );
                                                  }
                                                },
                                                child: const Text('Receipt'),
                                              )
                                            : const SizedBox.shrink()),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
