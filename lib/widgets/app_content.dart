import 'package:flutter_application_harbest_1/widgets/info_page.dart';

// ─────────────────────────────────────────────────────────────────────────
// Text and contact details shown on the My Account page.
// Fill these in here; no other file needs to change.
// ─────────────────────────────────────────────────────────────────────────

/// Help & Support → Contact Us → Email
const String kSupportEmail = 'HarBest@gmail.com';

/// Help & Support → Contact Us → Call us
const String kSupportPhone = '09212345678';

/// Terms & Privacy → Terms & Conditions
const List<InfoSection> kTermsSections = [
  InfoSection(
    heading: 'Terms & Conditions',
    body: 'TERMS & CONDITIONS FOR HarBest',
  ),
];

/// About Us
const List<InfoSection> kAboutSections = [
  InfoSection(
    heading: 'About HarBest',
    body:
        'HarBest helps you monitor your mustard green crop in real time with'
        'IoT sensors and AI-powered analytics.',
  ),
];
