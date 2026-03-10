import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'enroll_individual_tab.dart';
import 'enroll_bulk_tab.dart';
import 'enroll_gallery_tab.dart';

class EnrollScreen extends ConsumerStatefulWidget {
  const EnrollScreen({super.key});

  @override
  ConsumerState<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends ConsumerState<EnrollScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l.tabIndividual),
            Tab(text: l.tabBulk),
            Tab(text: l.tabGallery),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              IndividualTab(),
              BulkTab(),
              GalleryTab(),
            ],
          ),
        ),
      ],
    );
  }
}
