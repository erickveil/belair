import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      // Storage permissions
      // For Android 11+ (API 30+), MANAGE_EXTERNAL_STORAGE is needed for full access, 
      // but scoped storage is preferred.
      // However, for simplicity in this prototype, we'll ask for storage.
      
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      
      // For Android 13+ check for media permissions if needed, 
      // but for generic files "storage" might not be enough or deprecated.
      // We will also check manageExternalStorage if needed (usually restricted on Play Store but fine for side-loading/testing).
      
      if (!status.isGranted) {
         // Try manage external storage for Android 11+
         if (await Permission.manageExternalStorage.isPermanentlyDenied) {
            openAppSettings();
         } else {
            await Permission.manageExternalStorage.request();
         }
      }

      // Nearby devices (for Android 13+)
      if (await Permission.nearbyWifiDevices.status.isDenied) {
        await Permission.nearbyWifiDevices.request();
      }
    }
    
    // iOS/macOS permissions are handled via Info.plist/entitlements mostly,
    // but we can check if we have network permission (Local Network).
    // Permission.location might be needed for Wi-Fi info on some platforms.
    
    return true;
  }
}
