import 'package:flutter/material.dart';

class InsightsRecommendation extends StatefulWidget {
  const InsightsRecommendation({super.key});

  @override
  State<InsightsRecommendation> createState() => _InsightsRecommendationState();
}

class _InsightsRecommendationState extends State<InsightsRecommendation> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(child: _buildEmptyState()),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(
        top: 60,
        left: 20,
        right: 20,
        bottom: 20,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF7CB342),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: const Text(
        'AI Insights & Recommendations',
        style: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.lightbulb_outline_rounded,
                size: 56, color: Colors.black26),
            SizedBox(height: 16),
            Text(
              'No recommendations yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'AI insights and recommendations will appear here once they are available.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}