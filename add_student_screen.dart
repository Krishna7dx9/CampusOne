import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/app_providers.dart';
// Removed custom_fields import since custom section is no longer used
import '../../models/student.dart';
import '../../services/student_service.dart';

class AddStudentScreen extends ConsumerStatefulWidget {
  final Student? student; // if provided -> edit mode
  const AddStudentScreen({super.key, this.student});

  @override
  ConsumerState<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends ConsumerState<AddStudentScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _enrollNo = TextEditingController();
  final TextEditingController _name = TextEditingController();
  String _dept = '';
  String _year = '';
  String _status = 'active';
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Prefill in edit mode
    final s = widget.student;
    if (s != null) {
      _enrollNo.text = s.enrollNo;
      _name.text = s.name;
      _dept = s.dept;
      _year = s.year;
      _status = s.status;
      final email = (s.contactInfo['email'] as String?) ?? '';
      final phone = (s.contactInfo['phone'] as String?) ?? '';
      _email.text = email;
      _phone.text = phone;
    }
  }

  @override
  void dispose() {
    _enrollNo.dispose();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<bool> _enrollExists(String orgId, String enroll) async {
    final qs = await FirebaseFirestore.instance
        .collection('students')
        .where('orgId', isEqualTo: orgId)
        .where('enrollNo', isEqualTo: enroll)
        .limit(1)
        .get();
    return qs.docs.isNotEmpty;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final org = ref.read(currentOrgProvider).value;
    if (org == null) {
      setState(() => _error = 'Organization not loaded');
      return;
    }
    final String orgId = (org['id'] ?? org['orgId']) as String? ?? '';
    final String enroll = _enrollNo.text.trim();

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final editing = widget.student != null;
      if (!editing || (editing && widget.student!.enrollNo != enroll)) {
        if (await _enrollExists(orgId, enroll)) {
          setState(() => _error = 'Enrollment No already exists');
          return;
        }
      }

      final formId = _generateFormId();

      if (editing) {
        final student = widget.student!;
        final updated = student.copyWith(
          enrollNo: enroll,
          name: _name.text.trim(),
          dept: _dept.trim(),
          year: _year.trim(),
          status: _status,
          contactInfo: {
            if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
            if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
          },
          updatedAt: DateTime.now(),
        );
        await StudentService().updateStudent(updated, formId: formId);
      } else {
        final student = Student(
          id: '',
          orgId: orgId,
          userId: null,
          enrollNo: enroll,
          name: _name.text.trim(),
          dept: _dept.trim(),
          year: _year.trim(),
          status: _status,
          contactInfo: {
            if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
            if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
          },
          custom: const {},
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await StudentService().addStudent(student, formId: formId);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(editing ? 'Student updated' : 'Student added')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Failed to save student');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }

  String _generateFormId() {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');

    if (widget.student != null) {
      // Edit mode - use student's enrollment number
      return 'EDIT-${widget.student!.enrollNo}-$year$month$day';
    } else {
      // Add mode - generate new form ID
      return 'STU-$year$month$day$hour$minute';
    }
  }

  @override
  Widget build(BuildContext context) {
    const nirmaDepartments = <String>[
      'Computer Engineering (CSE)',
      'Information Technology (IT)',
      'Electronics & Communication (ECE)',
      'Electrical Engineering (EE)',
      'Mechanical Engineering (ME)',
      'Civil Engineering (CE)',
      'Chemical Engineering',
      'Biotechnology',
      'Automobile Engineering',
      'Instrumentation & Control',
      'Architecture',
      'Pharmacy',
      'MBA',
      'MCA',
    ];

    const semesters = <String>[
      '1st Semester',
      '2nd Semester',
      '3rd Semester',
      '4th Semester',
      '5th Semester',
      '6th Semester',
      '7th Semester',
      '8th Semester',
    ];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black87),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue[600],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.school,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.student == null ? 'Add Student' : 'Edit Student',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const Text(
                      'Student Management System',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
                const Spacer(),
                const Text(
                  'CampusOne ERP',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Form Header
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Student Registration',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        widget.student == null
                                            ? 'Complete all required fields to add a new student to the system'
                                            : 'Update student information',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: 16,
                                        color: Colors.grey[600],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Form ID: ${_generateFormId()}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),

                            // Student Information Section
                            _buildSection(
                              title: 'Student Information',
                              child: Column(
                                children: [
                                  TextFormField(
                                    controller: _enrollNo,
                                    decoration: InputDecoration(
                                      labelText: 'Enrollment No *',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                    ),
                                    validator: (v) =>
                                        (v == null || v.trim().isEmpty)
                                        ? 'Required'
                                        : null,
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _name,
                                    decoration: InputDecoration(
                                      labelText: 'Full Name *',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                    ),
                                    validator: (v) =>
                                        (v == null || v.trim().isEmpty)
                                        ? 'Required'
                                        : null,
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    initialValue: 'Active',
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      labelText: 'Status',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                      filled: true,
                                      fillColor: Colors.grey[50],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Academic Details Section
                            _buildSection(
                              title: 'Academic Details',
                              child: Column(
                                children: [
                                  DropdownButtonFormField<String>(
                                    initialValue:
                                        nirmaDepartments.contains(_dept)
                                        ? _dept
                                        : null,
                                    items: nirmaDepartments
                                        .map(
                                          (d) => DropdownMenuItem(
                                            value: d,
                                            child: Text(d),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) =>
                                        setState(() => _dept = v ?? ''),
                                    decoration: InputDecoration(
                                      labelText: 'Department *',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                    ),
                                    validator: (v) =>
                                        ((v ?? '').isEmpty) ? 'Required' : null,
                                  ),
                                  const SizedBox(height: 16),
                                  DropdownButtonFormField<String>(
                                    initialValue:
                                        const [
                                          '1',
                                          '2',
                                          '3',
                                          '4',
                                          '5',
                                        ].contains(_year)
                                        ? _year
                                        : null,
                                    items: const [
                                      DropdownMenuItem(
                                        value: '1',
                                        child: Text('1'),
                                      ),
                                      DropdownMenuItem(
                                        value: '2',
                                        child: Text('2'),
                                      ),
                                      DropdownMenuItem(
                                        value: '3',
                                        child: Text('3'),
                                      ),
                                      DropdownMenuItem(
                                        value: '4',
                                        child: Text('4'),
                                      ),
                                      DropdownMenuItem(
                                        value: '5',
                                        child: Text('5'),
                                      ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _year = v ?? ''),
                                    decoration: InputDecoration(
                                      labelText: 'Academic Year *',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                    ),
                                    validator: (v) =>
                                        ((v ?? '').isEmpty) ? 'Required' : null,
                                  ),
                                  const SizedBox(height: 16),
                                  DropdownButtonFormField<String>(
                                    initialValue:
                                        null, // Add semester field if needed
                                    items: semesters
                                        .map(
                                          (s) => DropdownMenuItem(
                                            value: s,
                                            child: Text(s),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) {
                                      // Handle semester selection
                                    },
                                    decoration: InputDecoration(
                                      labelText: 'Current Semester *',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Contact Information Section
                            _buildSection(
                              title: 'Contact Information',
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _email,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: InputDecoration(
                                        labelText: 'Email (optional)',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _phone,
                                      keyboardType: TextInputType.phone,
                                      decoration: InputDecoration(
                                        labelText: 'Phone Number (optional)',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  border: Border.all(color: Colors.red[200]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: Colors.red[600],
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: TextStyle(
                                          color: Colors.red[600],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Footer
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                const Text(
                  'CampusOne ERP v2.1.0',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const Spacer(),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Cancel'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check, size: 18),
                      label: Text(
                        widget.student == null
                            ? 'Register Student'
                            : 'Update Student',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
