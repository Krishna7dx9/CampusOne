import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher_string.dart';
// fl_chart import removed because charts are not used in top KPI refactor scope
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fees_screen.dart';
import 'students_list_screen.dart';
import 'rooms_grid_screen.dart';
import 'exams_screen.dart';
import 'billing_screen.dart';
import '../../core/app_providers.dart';
import '../../widgets/admin_shell.dart';

String _formatCurrency(num value) {
  try {
    // Use Indian locale style with rupee symbol; fallback to simple formatting
    return '₹${value.toStringAsFixed(0)}';
  } catch (_) {
    return '₹$value';
  }
}

class _SectionCard extends ConsumerWidget {
  final String title;
  const _SectionCard({required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(currentOrgProvider).value;
    final String? orgId = org != null
        ? (org['id'] ?? org['orgId']) as String?
        : null;

    Widget body = Text(
      'Loading... ',
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
      textAlign: TextAlign.center,
    );

    if (orgId != null) {
      if (title.contains('Admissions')) {
        final DateTime now = DateTime.now();
        final DateTime monthStart = DateTime(now.year, now.month, 1);
        final DateTime nextMonth = DateTime(now.year, now.month + 1, 1);
        final int daysInMonth = nextMonth.difference(monthStart).inDays;
        body = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('students')
              .where('orgId', isEqualTo: orgId)
              .where(
                'createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart),
              )
              .where('createdAt', isLessThan: Timestamp.fromDate(nextMonth))
              .snapshots(),
          builder: (context, s) {
            final buckets = List<int>.filled(daysInMonth, 0);
            if (s.hasData) {
              for (final d in s.data!.docs) {
                final ts = (d.data()['createdAt'] as Timestamp?)?.toDate();
                if (ts == null) continue;
                final day = DateTime(ts.year, ts.month, ts.day);
                if (day.isBefore(monthStart) || !day.isBefore(nextMonth)) {
                  continue;
                }
                final idx = day.difference(monthStart).inDays;
                if (idx >= 0 && idx < daysInMonth) buckets[idx] += 1;
              }
            }
            final hasAny = buckets.any((v) => v > 0);
            if (!hasAny) {
              return _CenterLines(lines: ['No admissions yet']);
            }
            final spots = <FlSpot>[];
            for (int i = 0; i < daysInMonth; i++) {
              spots.add(FlSpot((i + 1).toDouble(), buckets[i].toDouble()));
            }
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Expanded(
                    child: LineChart(
                      LineChartData(
                        lineTouchData: LineTouchData(
                          enabled: true,
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((t) {
                                final int day = t.x.toInt();
                                final DateTime date = DateTime(
                                  now.year,
                                  now.month,
                                  day,
                                );
                                return LineTooltipItem(
                                  '${date.day}/${date.month} \nAdmissions: ${t.y.toInt()}',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                        gridData: const FlGridData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 20,
                              getTitlesWidget: (v, _) {
                                final day = v.toInt();
                                if (day == 1 ||
                                    day == 10 ||
                                    day == 20 ||
                                    day == daysInMonth) {
                                  return Text(
                                    '$day',
                                    style: const TextStyle(fontSize: 10),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: Theme.of(context).colorScheme.primary,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 12,
                        height: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'This month',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      } else if (title.contains('Demographics')) {
        body = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('students')
              .where('orgId', isEqualTo: orgId)
              .snapshots(),
          builder: (context, s) {
            int cse = 0, ece = 0, me = 0, ce = 0, other = 0;
            if (s.hasData) {
              for (final d in s.data!.docs) {
                switch ((d.data()['dept'] as String? ?? '').toUpperCase()) {
                  case 'CSE':
                    cse++;
                    break;
                  case 'ECE':
                    ece++;
                    break;
                  case 'ME':
                    me++;
                    break;
                  case 'CE':
                    ce++;
                    break;
                  default:
                    other++;
                }
              }
            }
            final total = cse + ece + me + ce + other;
            if (total == 0) {
              return _CenterLines(lines: ['No student data yet']);
            }

            final colors = [
              Theme.of(context).colorScheme.primary,
              Colors.orange.shade600,
              Colors.green.shade600,
              Colors.purple.shade600,
              Colors.red.shade600,
            ];

            final sections = <PieChartSectionData>[];
            final depts = [
              {'name': 'CSE', 'count': cse, 'color': colors[0]},
              {'name': 'ECE', 'count': ece, 'color': colors[1]},
              {'name': 'ME', 'count': me, 'color': colors[2]},
              {'name': 'CE', 'count': ce, 'color': colors[3]},
              {'name': 'Other', 'count': other, 'color': colors[4]},
            ].where((d) => d['count'] as int > 0).toList();

            for (final dept in depts) {
              sections.add(
                PieChartSectionData(
                  color: dept['color'] as Color,
                  value: (dept['count'] as int).toDouble(),
                  title: '${dept['count']}',
                  radius: 50,
                  titleStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 30,
                        sections: sections,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: depts.map((dept) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: dept['color'] as Color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            dept['name'] as String,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          },
        );
      } else if (title.contains('Collection')) {
        body = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('fees')
              .where('orgId', isEqualTo: orgId)
              .snapshots(),
          builder: (context, s) {
            num paid = 0, pending = 0;
            if (s.hasData) {
              for (final d in s.data!.docs) {
                final data = d.data();
                final amount = (data['amount'] ?? 0) as num;
                final status = (data['status'] as String?) ?? 'pending';
                if (status == 'paid') {
                  paid += amount;
                } else if (status == 'pending')
                  pending += amount;
              }
            }
            final bool hasAnyData = (paid > 0) || (pending > 0);
            final Color collectedColor = Colors.green.shade600;
            final Color dueColor = Colors.orange.shade700;
            return Padding(
              padding: const EdgeInsets.all(8),
              child: hasAnyData
                  ? BarChart(
                      BarChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                switch (value.toInt()) {
                                  case 0:
                                    return const Text('Collected');
                                  case 1:
                                    return const Text('Pending');
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                        ),
                        barGroups: [
                          BarChartGroupData(
                            x: 0,
                            barRods: [
                              BarChartRodData(
                                toY: paid.toDouble(),
                                color: collectedColor,
                                width: 28,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ],
                          ),
                          BarChartGroupData(
                            x: 1,
                            barRods: [
                              BarChartRodData(
                                toY: pending.toDouble(),
                                color: dueColor,
                                width: 28,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : Center(
                      child: Text(
                        'No fee data yet',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ),
            );
          },
        );
      } else if (title.contains('Outstanding Fees')) {
        body = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('fees')
              .where('orgId', isEqualTo: orgId)
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (context, s) {
            num total = 0;
            if (s.hasData) {
              for (final d in s.data!.docs) {
                total += (d.data()['amount'] ?? 0) as num;
              }
            }
            return _CenterLines(
              lines: ['Total Pending', _formatCurrency(total)],
            );
          },
        );
      } else if (title.contains('Fee Collection Trends')) {
        body = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('fees')
              .where('orgId', isEqualTo: orgId)
              .where('status', isEqualTo: 'paid')
              .snapshots(),
          builder: (context, s) {
            final now = DateTime.now();
            final months = <String, num>{};

            // Initialize last 6 months
            for (int i = 5; i >= 0; i--) {
              final month = DateTime(now.year, now.month - i, 1);
              final key = '${month.month}/${month.year}';
              months[key] = 0;
            }

            if (s.hasData) {
              for (final d in s.data!.docs) {
                final paymentDate = (d.data()['paymentDate'] as Timestamp?)
                    ?.toDate();
                if (paymentDate == null) continue;

                final month = DateTime(paymentDate.year, paymentDate.month, 1);
                final key = '${month.month}/${month.year}';
                if (months.containsKey(key)) {
                  months[key] =
                      (months[key] ?? 0) + ((d.data()['amount'] ?? 0) as num);
                }
              }
            }

            final entries = months.entries.toList();
            final spots = <FlSpot>[];
            for (int i = 0; i < entries.length; i++) {
              spots.add(FlSpot(i.toDouble(), entries[i].value.toDouble()));
            }

            final hasData = spots.any((s) => s.y > 0);
            if (!hasData) {
              return _CenterLines(lines: ['No collection data yet']);
            }

            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Expanded(
                    child: LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 20,
                              getTitlesWidget: (v, _) {
                                final idx = v.toInt();
                                if (idx >= 0 && idx < entries.length) {
                                  final parts = entries[idx].key.split('/');
                                  return Text(
                                    '${parts[0]}/${parts[1].substring(2)}',
                                    style: const TextStyle(fontSize: 10),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: Colors.green.shade600,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 12,
                        height: 2,
                        color: Colors.green.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Collections',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      } else if (title.contains('Hostel')) {
        body = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('rooms')
              .where('orgId', isEqualTo: orgId)
              .snapshots(),
          builder: (context, s) {
            final Map<String, Map<String, int>> buildings = {};

            if (s.hasData) {
              for (final d in s.data!.docs) {
                final data = d.data();
                final building = (data['hostelId'] as String?) ?? 'Unknown';
                final capacity = (data['capacity'] ?? 0) as int;
                final occupancy = (data['occupancy'] ?? 0) as int;

                if (!buildings.containsKey(building)) {
                  buildings[building] = {'capacity': 0, 'occupancy': 0};
                }
                buildings[building]!['capacity'] =
                    (buildings[building]!['capacity'] ?? 0) + capacity;
                buildings[building]!['occupancy'] =
                    (buildings[building]!['occupancy'] ?? 0) + occupancy;
              }
            }

            if (buildings.isEmpty) {
              return _CenterLines(lines: ['No room data yet']);
            }

            final entries = buildings.entries.toList();
            final colors = [
              Theme.of(context).colorScheme.primary,
              Colors.orange.shade600,
              Colors.green.shade600,
              Colors.purple.shade600,
              Colors.red.shade600,
            ];

            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Expanded(
                    child: BarChart(
                      BarChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 20,
                              getTitlesWidget: (v, _) {
                                final idx = v.toInt();
                                if (idx >= 0 && idx < entries.length) {
                                  return Text(
                                    entries[idx].key,
                                    style: const TextStyle(fontSize: 10),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: entries.asMap().entries.map((e) {
                          final idx = e.key;
                          final entry =
                              e.value; // MapEntry<String, Map<String, int>>
                          final capacity = entry.value['capacity'] ?? 0;
                          final occupancy = entry.value['occupancy'] ?? 0;
                          final color = colors[idx % colors.length];

                          return BarChartGroupData(
                            x: idx,
                            barRods: [
                              BarChartRodData(
                                toY: capacity.toDouble(),
                                color: color.withOpacity(0.3),
                                width: 20,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              BarChartRodData(
                                toY: occupancy.toDouble(),
                                color: color,
                                width: 20,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 12,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Capacity',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(width: 16),
                      Container(
                        width: 12,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Occupied',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      } else {
        body = _CenterLines(
          lines: ['Quick actions', 'Use side menu for modules'],
        );
      }
    }

    return ConstrainedBox(
      constraints: const BoxConstraints.tightFor(width: 600, height: 260),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(child: body),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterLines extends StatelessWidget {
  final List<String> lines;
  const _CenterLines({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              l,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
      ],
    );
  }
}

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgSnap = ref.watch(currentOrgProvider);
    final TextEditingController searchController = TextEditingController();

    final Widget content = Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dashboard',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Icon(Icons.apartment, size: 16),
                              Text(
                                orgSnap.value != null
                                    ? ((orgSnap.value!['name'] as String?) ??
                                          (orgSnap.value!['id'] as String?) ??
                                          'Organization')
                                    : 'Organization',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context).hintColor,
                                    ),
                              ),
                              const Text('•'),
                              const Icon(Icons.dashboard_customize, size: 16),
                              Text(
                                'Admin',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context).hintColor,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox.shrink(),
                  ],
                ),
                const SizedBox(height: 12),
                // KPI row placed below the title
                if (orgSnap.isLoading)
                  const _SkeletonGrid()
                else if (orgSnap.hasError)
                  const Text('Failed to load organization')
                else if (orgSnap.value == null)
                  const Text('Organization not found')
                else ...[
                  LayoutBuilder(
                    builder: (context, c) {
                      final String orgId =
                          (orgSnap.value!['id'] ?? orgSnap.value!['orgId'])
                              as String;
                      // Five compact KPI cards in a single line that shrink to fit.
                      const double gap = 12;
                      return Row(
                        children: [
                          SizedBox(
                            width: (c.maxWidth - (4 * gap)) / 5,
                            child: _MetricTotalStudents(orgId: orgId),
                          ),
                          const SizedBox(width: gap),
                          SizedBox(
                            width: (c.maxWidth - (4 * gap)) / 5,
                            child: _MetricNewAdmissions(orgId: orgId),
                          ),
                          const SizedBox(width: gap),
                          SizedBox(
                            width: (c.maxWidth - (4 * gap)) / 5,
                            child: _MetricFeesCollected(orgId: orgId),
                          ),
                          const SizedBox(width: gap),
                          SizedBox(
                            width: (c.maxWidth - (4 * gap)) / 5,
                            child: _MetricFeesPending(orgId: orgId),
                          ),
                          const SizedBox(width: gap),
                          SizedBox(
                            width: (c.maxWidth - (4 * gap)) / 5,
                            child: _MetricHostelOccupancy(orgId: orgId),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                // Sections
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, c) {
                    // Force two cards per row on wide screens; Wrap will
                    // naturally stack on narrow screens
                    final double cardWidth = (c.maxWidth - 16) / 2;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: const _SectionCard(
                            title: 'Monthly Student Admissions',
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: const _SectionCard(
                            title: 'Student Demographics',
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: const _SectionCard(
                            title: 'Fee Collection Trends',
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: const _SectionCard(title: 'Outstanding Fees'),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: const _SectionCard(
                            title: 'Hostel Occupancy Status',
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: const _SectionCard(title: 'Quick Actions'),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),
                const _Footer(),
              ],
            ),
          ),
        ),
      ),
    );

    return AdminShell(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: AppBar(
          elevation: 1,
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                const SizedBox(width: 12),
                // Brand aligned with search/profile (moved from sidebar)
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade600,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.school,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'CampusOne ERP',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SizedBox(
                    height: 36,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchController,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, size: 20),
                              hintText: 'Search students, fees, or records...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              filled: true,
                            ),
                            onSubmitted: (q) {
                              final query = q.trim();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => StudentsListScreen(
                                    initialSearch: query.isEmpty ? null : query,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Simpler search: press Enter to go to Students with query
                        // (common search entry point)
                        const SizedBox(width: 0),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 8),
                _NotificationsBell(),
                IconButton(
                  tooltip: 'Help & Support',
                  icon: const Icon(Icons.help_outline),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (ctx) => const _HelpSheet(),
                    );
                  },
                ),
                const _UserMenu(),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
      sidebar: const _Sidebar(),
      body: content,
      scrollable: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    );
  }
}

// Legacy components kept earlier are now removed to match new design
// Removed: _TotalStudentsCard, _NewAdmissionsCard, _FeesCollectedCard,
// _FeesPendingCard, _HostelOccupancyCard, _KpiTile

/*
class _TotalStudentsCard extends StatelessWidget {
  final String orgId;
  const _TotalStudentsCard({required this.orgId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('students')
          .where('orgId', isEqualTo: orgId)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.size : 0;
        return const _KpiCard(
          title: 'Total Students',
          value: '',
        )._copyWithValue('$count');
      },
    );
  }
}

class _NewAdmissionsCard extends StatelessWidget {
  final String orgId;
  const _NewAdmissionsCard({required this.orgId});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('students')
          .where('orgId', isEqualTo: orgId)
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth),
          )
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.size : 0;
        return const _KpiCard(
          title: 'New Admissions',
          value: '',
        )._copyWithValue('$count');
      },
    );
  }
}

class _FeesCollectedCard extends StatelessWidget {
  final String orgId;
  const _FeesCollectedCard({required this.orgId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('fees')
          .where('orgId', isEqualTo: orgId)
          .where('status', isEqualTo: 'paid')
          .snapshots(),
      builder: (context, snapshot) {
        num collected = 0;
        if (snapshot.hasData) {
          for (final d in snapshot.data!.docs) {
            collected += (d.data()['amount'] ?? 0) as num;
          }
        }
        return const _KpiCard(
          title: 'Fees Collected',
          value: '',
        )._copyWithValue(_formatCurrency(collected));
      },
    );
  }
}

class _FeesPendingCard extends StatelessWidget {
  final String orgId;
  const _FeesPendingCard({required this.orgId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('fees')
          .where('orgId', isEqualTo: orgId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        num due = 0;
        if (snapshot.hasData) {
          for (final d in snapshot.data!.docs) {
            due += (d.data()['amount'] ?? 0) as num;
          }
        }
        return const _KpiCard(
          title: 'Fees Pending',
          value: '',
        )._copyWithValue(_formatCurrency(due));
      },
    );
  }
}

class _HostelOccupancyCard extends StatelessWidget {
  final String orgId;
  const _HostelOccupancyCard({required this.orgId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('rooms')
          .where('orgId', isEqualTo: orgId)
          .snapshots(),
      builder: (context, snapshot) {
        int capacity = 0;
        int occupancy = 0;
        if (snapshot.hasData) {
          for (final d in snapshot.data!.docs) {
            final data = d.data();
            capacity += (data['capacity'] ?? 0) as int;
            occupancy += (data['occupancy'] ?? 0) as int;
          }
        }
        final pct = capacity == 0 ? 0 : ((occupancy / capacity) * 100).round();
        return _KpiCard(
          title: 'Hostel Occupancy',
          value: '$occupancy/$capacity ($pct%)',
        );
      },
    );
  }
}

class _FeesBarChart extends StatefulWidget {
  final String orgId;
  const _FeesBarChart({required this.orgId});

  @override
  State<_FeesBarChart> createState() => _FeesBarChartState();
}

class _FeesBarChartState extends State<_FeesBarChart> {
  String _range = '30d'; // today | 7d | 30d | all

  DateTime? _startForRange() {
    final now = DateTime.now();
    switch (_range) {
      case 'today':
        return DateTime(now.year, now.month, now.day);
      case '7d':
        return now.subtract(const Duration(days: 7));
      case '30d':
        return now.subtract(const Duration(days: 30));
      case 'all':
      default:
        return null;
    }
  }

  void _setRange(String v) {
    if (v == _range) return;
    setState(() => _range = v);
  }

  @override
  Widget build(BuildContext context) {
    final Color collectedColor = Colors.green.shade600;
    final Color dueColor = Colors.orange.shade700;
    final DateTime? start = _startForRange();

    return SizedBox(
      height: 380,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Collections vs Due',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      _RangeChip(
                        label: 'Today',
                        value: 'today',
                        group: _range,
                        onSelected: _setRange,
                      ),
                      _RangeChip(
                        label: '7 days',
                        value: '7d',
                        group: _range,
                        onSelected: _setRange,
                      ),
                      _RangeChip(
                        label: '30 days',
                        value: '30d',
                        group: _range,
                        onSelected: _setRange,
                      ),
                      _RangeChip(
                        label: 'All',
                        value: 'all',
                        group: _range,
                        onSelected: _setRange,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: start == null
                    // No range -> single stream of org fees, compute client-side
                    ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('fees')
                            .where('orgId', isEqualTo: widget.orgId)
                            .snapshots(),
                        builder: (context, snapshot) {
                          num collected = 0;
                          num due = 0;
                          int countPaid = 0;
                          int countPending = 0;
                          int countFailed = 0;

                          if (snapshot.hasData) {
                            for (final d in snapshot.data!.docs) {
                              final data = d.data();
                              final amount = (data['amount'] ?? 0) as num;
                              final status =
                                  (data['status'] as String?) ?? 'pending';
                              if (status == 'paid') {
                                collected += amount;
                                countPaid++;
                              } else if (status == 'pending') {
                                due += amount;
                                countPending++;
                              } else if (status == 'failed') {
                                countFailed++;
                              }
                            }
                          }

                          return _FeesChartAndLegend(
                            collectedColor: collectedColor,
                            dueColor: dueColor,
                            collected: collected,
                            due: due,
                            countPaid: countPaid,
                            countPending: countPending,
                            countFailed: countFailed,
                          );
                        },
                      )
                    // Range active -> two filtered streams to minimize reads
                    : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('fees')
                            .where('orgId', isEqualTo: widget.orgId)
                            .where('status', isEqualTo: 'paid')
                            .where(
                              'paymentDate',
                              isGreaterThanOrEqualTo: Timestamp.fromDate(start),
                            )
                            .snapshots(),
                        builder: (context, paidSnap) {
                          return StreamBuilder<
                            QuerySnapshot<Map<String, dynamic>>
                          >(
                            stream: FirebaseFirestore.instance
                                .collection('fees')
                                .where('orgId', isEqualTo: widget.orgId)
                                .where('status', isEqualTo: 'pending')
                                .where(
                                  'dueDate',
                                  isGreaterThanOrEqualTo: Timestamp.fromDate(
                                    start,
                                  ),
                                )
                                .snapshots(),
                            builder: (context, pendingSnap) {
                              num collected = 0;
                              num due = 0;
                              int countPaid = 0;
                              int countPending = 0;
                              int countFailed =
                                  0; // not counted in filtered streams

                              if (paidSnap.hasData) {
                                for (final d in paidSnap.data!.docs) {
                                  final data = d.data();
                                  collected += (data['amount'] ?? 0) as num;
                                  countPaid++;
                                }
                              }
                              if (pendingSnap.hasData) {
                                for (final d in pendingSnap.data!.docs) {
                                  final data = d.data();
                                  due += (data['amount'] ?? 0) as num;
                                  countPending++;
                                }
                              }
                              return _FeesChartAndLegend(
                                collectedColor: collectedColor,
                                dueColor: dueColor,
                                collected: collected,
                                due: due,
                                countPaid: countPaid,
                                countPending: countPending,
                                countFailed: countFailed,
                              );
                            },
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              _RecentPaymentsList(orgId: widget.orgId, start: start),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeesChartAndLegend extends StatelessWidget {
  final Color collectedColor;
  final Color dueColor;
  final num collected;
  final num due;
  final int countPaid;
  final int countPending;
  final int countFailed;
  const _FeesChartAndLegend({
    required this.collectedColor,
    required this.dueColor,
    required this.collected,
    required this.due,
    required this.countPaid,
    required this.countPending,
    required this.countFailed,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasAnyData = (collected > 0) || (due > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _LegendDot(
              color: collectedColor,
              label: 'Collected: ${_formatCurrency(collected)}',
            ),
            _LegendDot(color: dueColor, label: 'Due: ${_formatCurrency(due)}'),
            if (countPaid > 0) Chip(label: Text('Paid: $countPaid')),
            if (countPending > 0) Chip(label: Text('Pending: $countPending')),
            if (countFailed > 0) Chip(label: Text('Failed: $countFailed')),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Stack(
            children: [
              BarChart(
                BarChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          switch (value.toInt()) {
                            case 0:
                              return const Text('Collected');
                            case 1:
                              return const Text('Due');
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: collected.toDouble(),
                          color: collectedColor,
                          width: 28,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: due.toDouble(),
                          color: dueColor,
                          width: 28,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!hasAnyData)
                Center(
                  child: Text(
                    'No data for selected period',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String label;
  final String value;
  final String group;
  final ValueChanged<String> onSelected;
  const _RangeChip({
    required this.label,
    required this.value,
    required this.group,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bool selected = value == group;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
    );
  }
}

class _RecentPaymentsList extends StatelessWidget {
  final String orgId;
  final DateTime? start;
  const _RecentPaymentsList({required this.orgId, required this.start});

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('fees')
        .where('orgId', isEqualTo: orgId)
        .where('status', isEqualTo: 'paid')
        .orderBy('paymentDate', descending: true)
        .limit(6);
    if (start != null) {
      q = q.where(
        'paymentDate',
        isGreaterThanOrEqualTo: Timestamp.fromDate(start!),
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Text(
            'No recent payments',
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              'Recent payments',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            ...docs.map((d) {
              final data = d.data();
              final String title = (data['title'] as String?) ?? 'Fee';
              final num amount = (data['amount'] ?? 0) as num;
              final Timestamp? ts = data['paymentDate'] as Timestamp?;
              final DateTime dt = ts?.toDate() ?? DateTime.now();
              final String yyyy = dt.year.toString();
              final String mm = dt.month.toString().padLeft(2, '0');
              final String dd = dt.day.toString().padLeft(2, '0');
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text(title),
                subtitle: Text('$yyyy-$mm-$dd'),
                trailing: Text(
                  _formatCurrency(amount),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  const _KpiCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 88,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).hintColor,
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on _KpiCard {
  _KpiCard _copyWithValue(String v) => _KpiCard(title: title, value: v);
}

class _KpiTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Widget child;
  const _KpiTile({
    required this.icon,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 8),
          child,
        ],
      ),
    );
  }
}
*/

// Material-like metric card variants to match the provided UI screenshot
class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String? subtext;
  const _MetricCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    this.subtext,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (subtext != null && subtext!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtext!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).hintColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricTotalStudents extends StatelessWidget {
  final String orgId;
  const _MetricTotalStudents({required this.orgId});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('students')
          .where('orgId', isEqualTo: orgId)
          .snapshots(),
      builder: (context, s) {
        final n = s.hasData ? s.data!.size : 0;
        return _MetricCard(
          icon: Icons.people_outline_rounded,
          color: Colors.indigo,
          title: 'Total Students',
          value: '$n',
        );
      },
    );
  }
}

class _MetricNewAdmissions extends StatelessWidget {
  final String orgId;
  const _MetricNewAdmissions({required this.orgId});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('students')
          .where('orgId', isEqualTo: orgId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .snapshots(),
      builder: (context, s) {
        final n = s.hasData ? s.data!.size : 0;
        return _MetricCard(
          icon: Icons.person_add_alt_1_rounded,
          color: Colors.blue,
          title: 'New Admissions',
          value: '$n',
        );
      },
    );
  }
}

class _MetricFeesCollected extends StatelessWidget {
  final String orgId;
  const _MetricFeesCollected({required this.orgId});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('fees')
          .where('orgId', isEqualTo: orgId)
          .where('status', isEqualTo: 'paid')
          .snapshots(),
      builder: (context, s) {
        num sum = 0;
        if (s.hasData) {
          for (final d in s.data!.docs) {
            sum += (d.data()['amount'] ?? 0) as num;
          }
        }
        return _MetricCard(
          icon: Icons.monetization_on_outlined,
          color: Colors.green,
          title: 'Fees Collected',
          value: _formatCurrency(sum),
        );
      },
    );
  }
}

class _MetricFeesPending extends StatelessWidget {
  final String orgId;
  const _MetricFeesPending({required this.orgId});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('fees')
          .where('orgId', isEqualTo: orgId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, s) {
        num sum = 0;
        if (s.hasData) {
          for (final d in s.data!.docs) {
            sum += (d.data()['amount'] ?? 0) as num;
          }
        }
        return _MetricCard(
          icon: Icons.receipt_long_outlined,
          color: Colors.orange,
          title: 'Fees Pending',
          value: _formatCurrency(sum),
        );
      },
    );
  }
}

class _MetricHostelOccupancy extends StatelessWidget {
  final String orgId;
  const _MetricHostelOccupancy({required this.orgId});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('rooms')
          .where('orgId', isEqualTo: orgId)
          .snapshots(),
      builder: (context, s) {
        int capacity = 0, occ = 0;
        if (s.hasData) {
          for (final d in s.data!.docs) {
            final m = d.data();
            capacity += (m['capacity'] ?? 0) as int;
            occ += (m['occupancy'] ?? 0) as int;
          }
        }
        final pct = capacity == 0 ? 0 : ((occ / capacity) * 100).round();
        return _MetricCard(
          icon: Icons.meeting_room_outlined,
          color: Colors.purple,
          title: 'Hostel Occupancy',
          value: '$pct%',
          subtext: capacity > 0 ? '$occ/$capacity rooms occupied' : null,
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).hintColor,
          letterSpacing: .6,
        ),
      ),
    );
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          const SizedBox(height: 4),
          const Divider(height: 1),
          section('MAIN'),
          // Show current page as non-interactive selected item
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            selected: true,
            selectedTileColor: Theme.of(
              context,
            ).colorScheme.primary.withOpacity(0.08),
            enabled: false,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          section('MODULES'),
          _SideItem(
            icon: Icons.people,
            label: 'Students',
            trailing: _CountBadge(
              query: (orgId) => FirebaseFirestore.instance
                  .collection('students')
                  .where('orgId', isEqualTo: orgId),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StudentsListScreen()),
            ),
          ),
          _SideItem(
            icon: Icons.receipt_long,
            label: 'Fees',
            trailing: _CountBadge(
              query: (orgId) => FirebaseFirestore.instance
                  .collection('fees')
                  .where('orgId', isEqualTo: orgId)
                  .where('status', isEqualTo: 'pending'),
              color: Colors.orange,
            ),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const FeesScreen())),
          ),
          _SideItem(
            icon: Icons.meeting_room,
            label: 'Rooms',
            trailing: _CountBadge(
              query: (orgId) => FirebaseFirestore.instance
                  .collection('rooms')
                  .where('orgId', isEqualTo: orgId)
                  .where('status', isEqualTo: 'available'),
              color: Colors.green,
            ),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const RoomsGridScreen())),
          ),
          _SideItem(
            icon: Icons.event_note,
            label: 'Exams',
            trailing: _CountBadge(
              query: (orgId) => FirebaseFirestore.instance
                  .collection('exams')
                  .where('orgId', isEqualTo: orgId)
                  .where('published', isEqualTo: true),
              color: Colors.indigo,
            ),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ExamsScreen())),
          ),
          const Divider(height: 1),
          section('BILLING'),
          _SideItem(
            icon: Icons.payments,
            label: 'Billing',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const BillingScreen())),
          ),
        ],
      ),
    );
  }
}

class _SideItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  const _SideItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  @override
  State<_SideItem> createState() => _SideItemState();
}

class _SideItemState extends State<_SideItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bool isDashboard = widget.label.toLowerCase() == 'dashboard';
    final Color primary = Theme.of(context).colorScheme.primary;
    final Color? iconColor = isDashboard ? primary : null;
    final TextStyle? titleStyle = isDashboard
        ? TextStyle(color: primary, fontWeight: FontWeight.w600)
        : null;
    final Color hoverBg = primary.withOpacity(0.06);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        selected: isDashboard,
        selectedTileColor: primary.withOpacity(0.08),
        tileColor: _hovering && !isDashboard ? hoverBg : null,
        leading: Icon(widget.icon, color: iconColor),
        title: Text(widget.label, style: titleStyle),
        trailing: widget.trailing,
        onTap: () {
          Navigator.of(context).pop();
          widget.onTap();
        },
      ),
    );
  }
}

class _CountBadge extends ConsumerWidget {
  final Query<Map<String, dynamic>> Function(String orgId) query;
  final Color? color;
  const _CountBadge({required this.query, this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(currentOrgProvider).value;
    final String? orgId = org != null
        ? (org['id'] ?? org['orgId']) as String?
        : null;
    if (orgId == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // Use a full live snapshot to keep counts accurate and dynamic.
      // For very large datasets, consider switching to Firestore count() aggregation.
      stream: query(orgId).snapshots(),
      builder: (context, snapshot) {
        final n = snapshot.hasData ? snapshot.data!.size : 0;
        if (n == 0) return const SizedBox.shrink();
        final bg = (color ?? Theme.of(context).colorScheme.primary).withOpacity(
          .12,
        );
        final fg = color ?? Theme.of(context).colorScheme.primary;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$n',
            style: TextStyle(color: fg, fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }
}

// Drawer is now handled by AdminShell for narrow screens via its sidebar

// Removed unused _HeaderAction (moved actions to AppBar)

class _UserMenu extends ConsumerWidget {
  const _UserMenu();

  Future<void> _confirmAndSignOut(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Signed out')));
      }
    }
  }

  void _openAccountDialog(BuildContext context, String email, String role) {
    final String initials = email.isNotEmpty
        ? email.substring(0, 1).toUpperCase()
        : 'A';
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            CircleAvatar(radius: 16, child: Text(initials)),
            const SizedBox(width: 8),
            const Text('Account'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Chip(label: Text(role), visualDensity: VisualDensity.compact),
            const SizedBox(height: 8),
            Text(
              'Choose an action',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(),
            icon: const Icon(Icons.close),
            label: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await Future.delayed(const Duration(milliseconds: 50));
              _confirmAndSignOut(context);
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUser = ref.watch(authStateProvider).value;
    final appUser = ref.watch(currentUserProvider).value;
    final String initials =
        (appUser?.email ?? authUser?.email ?? 'A').trim().isNotEmpty
        ? (appUser?.email ?? authUser?.email ?? 'A')
              .substring(0, 1)
              .toUpperCase()
        : 'A';
    final String email = appUser?.email ?? authUser?.email ?? '';
    final String role = appUser?.role.toUpperCase() ?? 'USER';

    return IconButton(
      tooltip: 'Account',
      onPressed: () => _openAccountDialog(context, email, role),
      icon: CircleAvatar(radius: 16, child: Text(initials)),
    );
  }
}

class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();
  @override
  Widget build(BuildContext context) {
    Widget skel() => Container(
      width: 280,
      height: 120,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
    );
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [skel(), skel(), skel(), skel()],
    );
  }
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  void _open(BuildContext context, Widget child) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Help & Support',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'For assistance, contact your administrator or email support@campusone.edu.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('FAQ'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _open(context, const _FaqSheet()),
                ),
                ActionChip(
                  label: const Text('User Guide'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _open(context, const _UserGuideSheet()),
                ),
                ActionChip(
                  label: const Text('Report an Issue'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _open(context, const _ReportIssueSheet()),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqSheet extends StatelessWidget {
  const _FaqSheet();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline),
              const SizedBox(width: 8),
              Text(
                'Frequently Asked Questions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Q: How do I add a student?\nA: Go to Students → Add.'),
          const SizedBox(height: 8),
          const Text(
            'Q: How to mark fees as paid?\nA: Open Fees → select fee → Mark Paid.',
          ),
        ],
      ),
    );
  }
}

class _UserGuideSheet extends StatelessWidget {
  const _UserGuideSheet();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.menu_book_outlined),
              const SizedBox(width: 8),
              Text(
                'User Guide',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '1. Dashboard overview\n2. Managing students\n3. Fees workflows\n4. Exams & results',
          ),
        ],
      ),
    );
  }
}

class _ReportIssueSheet extends StatelessWidget {
  const _ReportIssueSheet();
  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report_outlined),
              const SizedBox(width: 8),
              Text(
                'Report an Issue',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Describe the issue... ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Issue reported. Thank you.')),
                );
              },
              child: const Text('Submit'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationsSheet extends StatelessWidget {
  final String orgId;
  const _NotificationsSheet({required this.orgId});

  @override
  Widget build(BuildContext context) {
    return _NotificationsSheetStateful(orgId: orgId);
  }
}

class _NotificationsSheetStateful extends StatefulWidget {
  final String orgId;
  const _NotificationsSheetStateful({required this.orgId});

  @override
  State<_NotificationsSheetStateful> createState() =>
      _NotificationsSheetStatefulState();
}

class _NotificationsSheetStatefulState
    extends State<_NotificationsSheetStateful> {
  String _filter = 'all'; // all | fees | exam | hostel

  @override
  Widget build(BuildContext context) {
    final Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('notifications')
        .where('orgId', isEqualTo: widget.orgId)
        .orderBy('createdAt', descending: true)
        .limit(10);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Notifications',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter == 'all',
                  onSelected: (_) => setState(() => _filter = 'all'),
                ),
                ChoiceChip(
                  label: const Text('Fees'),
                  selected: _filter == 'fees',
                  onSelected: (_) => setState(() => _filter = 'fees'),
                ),
                ChoiceChip(
                  label: const Text('Exams'),
                  selected: _filter == 'exam',
                  onSelected: (_) => setState(() => _filter = 'exam'),
                ),
                ChoiceChip(
                  label: const Text('Hostel'),
                  selected: _filter == 'hostel',
                  onSelected: (_) => setState(() => _filter = 'hostel'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Unable to load notifications.'),
                  );
                }
                final docs = snapshot.data!.docs;
                final filtered = docs.where((d) {
                  final data = d.data();
                  final String? type = data['type'] as String?;
                  final String? title = data['title'] as String?;
                  if (title == null || title.trim().isEmpty) return false;
                  final bool typeOk =
                      type == 'fees' || type == 'exam' || type == 'hostel';
                  if (!typeOk) return false;
                  if (_filter == 'all') return true;
                  return type == _filter;
                }).toList();
                if (filtered.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No notifications available.'),
                  );
                }
                return Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final data = filtered[index].data();
                      final String title =
                          (data['title'] as String?) ?? 'Notification';
                      final String? body = data['body'] as String?;
                      final String type = (data['type'] as String?) ?? 'info';
                      final Timestamp? ts = data['createdAt'] as Timestamp?;
                      final DateTime dt = ts?.toDate() ?? DateTime.now();
                      final String dd = dt.day.toString().padLeft(2, '0');
                      final String mm = dt.month.toString().padLeft(2, '0');
                      final String yyyy = dt.year.toString();
                      IconData lead = Icons.notifications;
                      if (type == 'fees') lead = Icons.payments;
                      if (type == 'exam') lead = Icons.event_note;
                      if (type == 'hostel') lead = Icons.meeting_room;
                      return ListTile(
                        dense: true,
                        leading: Icon(lead),
                        title: Text(title),
                        subtitle: (body != null && body.trim().isNotEmpty)
                            ? Text(body)
                            : null,
                        trailing: Text(
                          '$dd-$mm-$yyyy',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsBell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(currentOrgProvider).value;
    final String? orgId = org != null
        ? (org['id'] ?? org['orgId']) as String?
        : null;
    if (orgId == null) {
      return IconButton(
        tooltip: 'Notifications',
        icon: const Icon(Icons.notifications_none),
        onPressed: null,
      );
    }
    final q = FirebaseFirestore.instance
        .collection('notifications')
        .where('orgId', isEqualTo: orgId)
        .orderBy('createdAt', descending: true)
        .limit(1);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snapshot) {
        final hasAny = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
        Widget bell = IconButton(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_none),
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (ctx) => _NotificationsSheet(orgId: orgId),
            );
          },
        );
        if (!hasAny) return bell;
        return Stack(
          alignment: Alignment.topRight,
          children: [
            bell,
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = DateTime.now().year;
    final org = ref.watch(currentOrgProvider).value;
    final String orgName = org != null
        ? ((org['name'] as String?) ?? (org['id'] as String?) ?? 'CampusOne')
        : 'CampusOne';
    final Color dim = Theme.of(context).hintColor;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(color: Theme.of(context).dividerColor),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final double colWidth = (c.maxWidth - 24) / 4;
              return Wrap(
                spacing: 8,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: colWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade600,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.school,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'CampusOne ERP',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Simple, low-cost ERP for colleges. Live dashboards, fees, hostel, exams.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: dim),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: colWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ACADEMICS',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                letterSpacing: 1.0,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _FooterLink(label: 'Student management', onTap: () {}),
                        _FooterLink(label: 'Results', onTap: () {}),
                        _FooterLink(label: 'Timetable', onTap: () {}),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: colWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CAMPUS',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                letterSpacing: 1.0,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _FooterLink(label: 'Hostel/Rooms', onTap: () {}),
                        _FooterLink(label: 'Fee collections', onTap: () {}),
                        _FooterLink(label: 'Billing', onTap: () {}),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: colWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SUPPORT',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                letterSpacing: 1.0,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _FooterLink(
                          label: 'Help center',
                          onTap: () => _openUrl('https://example.com/help'),
                        ),
                        _FooterLink(
                          label: 'Contact',
                          onTap: () => _openUrl('mailto:support@example.com'),
                        ),
                        _FooterLink(
                          label: 'Privacy policy',
                          onTap: () => _openUrl('https://example.com/privacy'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '© $year $orgName • All rights reserved',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: dim),
              ),
              const SizedBox(width: 12),
              Text(
                'v1.0.0',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: dim),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FooterLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _openUrl(String url) {
  launchUrlString(url, mode: LaunchMode.externalApplication);
}
