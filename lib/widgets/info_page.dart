import 'package:flutter/material.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_card.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';

/// One block of text on an [InfoPage]: an optional heading and a paragraph.
class InfoSection {
  final String? heading;
  final String body;
  const InfoSection({this.heading, required this.body});
}

/// Simple reading page (Terms & Conditions, About Us...). Pass the text in
/// as [sections]; the text itself lives in content/app_content.dart.
class InfoPage extends StatelessWidget {
  final String title;
  final List<InfoSection> sections;

  const InfoPage({super.key, required this.title, required this.sections});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppHeader(title: title, showBack: true),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.page),
              child: SizedBox(
                width: double.infinity,
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpace.cardGap),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final s in sections) ...[
                        if (s.heading != null) ...[
                          Text(s.heading!, style: AppText.cardTitle),
                          const SizedBox(height: 8),
                        ],
                        Text(s.body, style: AppText.body.copyWith(height: 1.5)),
                        const SizedBox(height: AppSpace.cardGap),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}