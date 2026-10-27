import 'package:flutter_test/flutter_test.dart';
import 'package:mimbar/ui/host_actions.dart';

void main() {
  test('WhatsApp numbers are international without the plus', () {
    expect(whatsappNumber('03001234567'), '923001234567');
    expect(whatsappNumber('+966568619990'), '966568619990');
    expect(whatsappNumber('+18452816085'), '18452816085');
  });
}
