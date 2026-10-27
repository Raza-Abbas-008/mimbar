import 'package:flutter/services.dart';

/// A contact picked from the phone's Contacts app.
class PickedContact {
  final String name;

  /// The default number first, then the most recently added.
  final List<String> phones;
  const PickedContact(this.name, this.phones);
}

/// The "mimbar/native" channel (see MainActivity.kt).
class NativeBridge {
  static const _ch = MethodChannel('mimbar/native');

  static const facebook = 'com.facebook.katana';
  static const whatsapp = ['com.whatsapp', 'com.whatsapp.w4b'];

  /// Sends text and/or an image straight to one app. False if that app
  /// isn't installed.
  static Future<bool> shareTo(String package,
          {String? text, String? path}) async =>
      await _ch.invokeMethod<bool>(
          'shareTo', {'package': package, 'text': text, 'path': path}) ??
      false;

  /// Opens the contact picker. Returns null if cancelled; throws
  /// [ContactsDenied] if the Contacts permission was refused.
  static Future<PickedContact?> pickContact() async {
    final r = await _ch.invokeMapMethod<String, dynamic>('pickContact');
    if (r == null) return null;
    if (r['denied'] == true) throw const ContactsDenied();
    return PickedContact(
        r['name'] as String? ?? '', List<String>.from(r['phones'] as List));
  }

  /// An image another app shared into Mimbar at launch, if any.
  static Future<String?> takeSharedImage() =>
      _ch.invokeMethod<String>('takeSharedImage');

  /// Called when an image is shared in while Mimbar is already open.
  static void onSharedImage(void Function(String path) handler) =>
      _ch.setMethodCallHandler((call) async {
        if (call.method == 'sharedImage') handler(call.arguments as String);
      });
}

class ContactsDenied implements Exception {
  const ContactsDenied();
}
