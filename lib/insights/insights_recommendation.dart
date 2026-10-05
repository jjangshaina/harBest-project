import 'package:flutter/material.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/app_empty_state.dart';

class InsightsRecommendation extends StatefulWidget {
  const InsightsRecommendation({super.key});

  @override
  State<InsightsRecommendation> createState() => _InsightsRecommendationState();
}

class _InsightsRecommendationState extends State<InsightsRecommendation> {
  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        AppHeader(title: 'AI Insights & Recommendations'),
        Expanded(
          child: AppEmptyState(
            icon: AppIcons.tip,
            title: 'No recommendations yet',
            message:
                'AI insights and recommendations will appear here once they are available.',
          ),
        ),
      ],
    );
  }
}