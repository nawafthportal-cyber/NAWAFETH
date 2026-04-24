import 'account_mode_service.dart';
import 'profile_service.dart';

class AccountModeSyncService {
  static Future<String> resolveApiMode() async {
    final fallbackMode = await AccountModeService.apiMode();
    final result = await ProfileService.fetchMyProfile();
    if (!result.isSuccess || result.data == null) {
      return fallbackMode;
    }

    final profile = result.data!;
    final canUseProvider = profile.isProvider || profile.hasProviderProfile;
    final savedProviderMode = await AccountModeService.isProviderMode();
    final effectiveProviderMode = canUseProvider ? savedProviderMode : false;

    await AccountModeService.setProviderMode(effectiveProviderMode);
    return effectiveProviderMode ? 'provider' : 'client';
  }
}