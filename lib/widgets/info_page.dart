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
///
/// With [collapsible] true, only the first section shows at first and a
/// "Read more" link below it expands the rest (the link becomes "Read less").
class InfoPage extends StatefulWidget {
  final String title;
  final List<InfoSection> sections;
  final bool collapsible;

  const InfoPage({
    super.key,
    required this.title,
    required this.sections,
    this.collapsible = false,
  });

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  bool _expanded = false;

  Widget _section(InfoSection s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.heading != null) ...[
          Text(s.heading!, style: AppText.cardTitle),
          const SizedBox(height: 8),
        ],
        Text(s.body, style: AppText.body.copyWith(height: 1.5)),
        const SizedBox(height: AppSpace.cardGap),
      ],
    );
  }

  Widget _toggleLink() {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          _expanded ? 'Read less' : 'Read more',
          style: const TextStyle(
            color: AppColors.darkGreen,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.darkGreen,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = widget.sections;
    final canCollapse = widget.collapsible && sections.length > 1;

    return Scaffold(
      body: Column(
        children: [
          AppHeader(title: widget.title, showBack: true),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.page),
              child: SizedBox(
                width: double.infinity,
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpace.cardGap),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: canCollapse
                        ? [
                            _section(sections.first),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                              alignment: Alignment.topCenter,
                              child: _expanded
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (final s in sections.skip(1))
                                          _section(s),
                                      ],
                                    )
                                  : const SizedBox(width: double.infinity),
                            ),
                            _toggleLink(),
                          ]
                        : [for (final s in sections) _section(s)],
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