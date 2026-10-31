import 'package:flutter_application_harbest_1/widgets/info_page.dart';

// ─────────────────────────────────────────────────────────────────────────
// Text and contact details shown on the My Account page.
// Fill these in here; no other file needs to change.
// ─────────────────────────────────────────────────────────────────────────

/// Help & Support → Contact Us → Email
const String kSupportEmail = 'Harbestcropanalytics@gmail.com';

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
        'HarBest helps you monitor your crop with IoT sensors '
        'and AI-powered analytics. It is built for home-based urban gardeners '
        'and small community gardens, where space is limited but healthy, '
        'well-managed plants still matter.',
  ),
  InfoSection(
    heading: 'The HarBest device',
    body:
        'Your HarBest device sits with your crop and measures its growing '
        'conditions: soil pH, soil moisture, temperature, humidity, heat '
        'index, soil EC, and the nutrients nitrogen, phosphorus and '
        'potassium. It sends these readings to the app automatically, so '
        'you can check on your plants anytime.',
  ),
  InfoSection(
    heading: 'The HarBest app',
    body:
        'The Dashboard shows your latest readings and overall crop health at '
        'a glance. Analytics looks at trends and relationships in your '
        'sensor data over time. Plant Profile tracks your crop through its '
        'growth stages and gives practical recommendations when a reading '
        'drifts outside its ideal range. Forecast previews how conditions '
        'may change, and Alerts tells you when your sensors detect a '
        'problem.',
  ),
  InfoSection(
    heading: 'Our goal',
    body:
        'By combining IoT sensing, machine learning and clear data '
        'visualization, HarBest helps you understand your plants\' growing '
        'conditions, spot potential crop health concerns early, and make '
        'informed decisions about plant care, so your crops grow healthier '
        'even in small spaces.',
  ),
];
