import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  group('blockedContacts setting', () {
    test('defaults to empty', () {
      expect(AppSettings().blockedContacts, isEmpty);
    });

    test('toJson/fromJson round-trips and lowercases keys', () {
      final settings = AppSettings(blockedContacts: {'AABB', 'ccdd'});
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.blockedContacts, {'aabb', 'ccdd'});
    });

    test('fromJson without the field yields an empty set', () {
      final restored = AppSettings.fromJson(const {});
      expect(restored.blockedContacts, isEmpty);
    });

    test('copyWith keeps and replaces blockedContacts', () {
      final settings = AppSettings(blockedContacts: {'aa'});
      expect(settings.copyWith().blockedContacts, {'aa'});
      expect(settings.copyWith(blockedContacts: {'bb'}).blockedContacts, {
        'bb',
      });
    });
  });

  group('blockedNames setting', () {
    test('round-trips through json without changing case', () {
      final settings = AppSettings(blockedNames: {'Bruno', 'bruno'});
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.blockedNames, {'Bruno', 'bruno'});
    });

    test('fromJson without the field yields an empty set', () {
      expect(AppSettings.fromJson(const {}).blockedNames, isEmpty);
    });
  });

  group('AppSettingsService name blocking', () {
    test('matches the exact name only', () async {
      final service = AppSettingsService();
      await service.blockName('Bruno');
      expect(service.isNameBlocked('Bruno'), isTrue);
      expect(service.isNameBlocked('bruno'), isFalse);
      await service.unblockName('Bruno');
      expect(service.isNameBlocked('Bruno'), isFalse);
    });
  });

  group('AppSettingsService block/unblock', () {
    test('block then unblock toggles isContactBlocked', () async {
      final service = AppSettingsService();
      expect(service.isContactBlocked('AABB'), isFalse);

      await service.blockContact('AABB');
      expect(service.isContactBlocked('aabb'), isTrue);
      expect(service.isContactBlocked('AABB'), isTrue);
      expect(service.isContactBlocked('ccdd'), isFalse);

      await service.unblockContact('aabb');
      expect(service.isContactBlocked('AABB'), isFalse);
    });

    test('blocking is idempotent', () async {
      final service = AppSettingsService();
      await service.blockContact('aabb');
      await service.blockContact('AABB');
      expect(service.settings.blockedContacts, {'aabb'});
    });
  });
}
