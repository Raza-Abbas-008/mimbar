import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/strings.dart';
import '../data/models.dart';

/// The number in international form without "+", as wa.me wants it.
/// Local Pakistani numbers (03xx…) become 923xx….
String whatsappNumber(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (phone.startsWith('+')) return digits;
  if (digits.startsWith('0')) return '92${digits.substring(1)}';
  return digits;
}

Future<void> copyHostNumber(BuildContext context, Host h) async {
  await Clipboard.setData(ClipboardData(text: h.phone));
  if (context.mounted) _toast(context, tr(context, 'number_copied'));
}

/// Opens the dialer with the number filled in, where the SIM is chosen.
Future<void> callHost(BuildContext context, Host h) async {
  if (!await launchUrl(Uri(scheme: 'tel', path: h.phone)) && context.mounted) {
    _toast(context, h.phone);
  }
}

Future<void> whatsappHost(BuildContext context, Host h) async {
  final ok = await launchUrl(
      Uri.parse('https://wa.me/${whatsappNumber(h.phone)}'),
      mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    _toast(context, '${tr(context, 'whatsapp')} ${tr(context, 'not_installed')}');
  }
}

void _toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
