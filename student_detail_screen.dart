import 'package:flutter/material.dart';
import '../../models/student.dart';

class StudentDetailScreenStandalone extends StatelessWidget {
  const StudentDetailScreenStandalone({super.key, required this.student});
  final Student student;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(student.name)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enrollment: ${student.enrollNo}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Department: ${student.dept}'),
            Text('Year: ${student.year}'),
            Text('Status: ${student.status}'),
            const SizedBox(height: 16),
            Text('Contact: ${student.contactInfo.toString()}'),
            const SizedBox(height: 8),
            Text('Academic: ${student.academicInfo.toString()}'),
            const SizedBox(height: 16),
            Text('Custom: ${student.custom.toString()}'),
          ],
        ),
      ),
    );
  }
}
