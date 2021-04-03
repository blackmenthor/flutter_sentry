import 'dart:io';

import 'package:device_info/device_info.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info/package_info.dart';
import 'package:sentry/sentry.dart' as sentry;

import '../flutter_sentry.dart';

AndroidDeviceInfo _androidDeviceInfo;
IosDeviceInfo _iosDeviceInfo;
PackageInfo _packageInfo;
DateTime _firstPrefetchTime;
bool _firebaseTestLab;

/// Since the current implementation of contexts_cache is a true singleton,
/// there's no way to pass a mocked value in tests, so we resort to this ugly
/// method.
@visibleForTesting
set packageInfo(PackageInfo value) => _packageInfo = value;

/// Initialize internal state by asynchronously fetching various information
/// about device, OS and app.
void prefetch() {
  _firstPrefetchTime ??= DateTime.now();
  WidgetsFlutterBinding.ensureInitialized();

  final deviceInfo = DeviceInfoPlugin();
  if (Platform.isAndroid) {
    deviceInfo.androidInfo.then((info) => _androidDeviceInfo = info);
  } else if (Platform.isIOS) {
    deviceInfo.iosInfo.then((info) => _iosDeviceInfo = info);
  }

  FlutterSentry.isFirebaseTestLab().then((value) => _firebaseTestLab = value);
  if (_packageInfo == null) {
    PackageInfo.fromPlatform().then((info) => _packageInfo = info);
  }
}

/// Get default value of "release" `Event` field, as normally generated by
/// platform-specific code.
String defaultReleaseString() => _packageInfo == null
    ? null
    : '${_packageInfo.packageName}@'
        '${_packageInfo.version}+${_packageInfo.buildNumber}';

/// Snapshot of the current device state, including information obtained in
/// [prefetch].
sentry.Contexts currentContexts() => sentry.Contexts(
      app: sentry.App(
        startTime: _firstPrefetchTime,
        identifier: _packageInfo?.packageName,
        name: _packageInfo?.appName,
        version: _packageInfo?.version,
        build: _packageInfo?.buildNumber,
      ),
      operatingSystem: _androidDeviceInfo == null
          ? _iosDeviceInfo == null
              ? null
              : sentry.OperatingSystem(
                  name: 'iOS',
                  version: _iosDeviceInfo.systemVersion,
                  kernelVersion: _iosDeviceInfo.utsname.version,
                )
          : sentry.OperatingSystem(
              name: 'Android',
              version: _androidDeviceInfo.version.release,
              build: _androidDeviceInfo.id,
            ),
      device: _deviceContext(),
      runtimes: [
        if (_firebaseTestLab == true)
          const sentry.SentryRuntime(
            key: 'Firebase Test Lab',
            name: 'Firebase Test Lab or Pre-launch report',
          ),
      ],
    );

sentry.Device _deviceContext() {
  // Have to go with a list of variables because sentry.Device is immutable:
  // https://github.com/flutter/flutter/issues/53522.
  String name, model, manufacturer, family, brand, arch;
  bool simulator;

  if (_androidDeviceInfo != null) {
    name = _androidDeviceInfo.device;
    model = _androidDeviceInfo.model;
    manufacturer = _androidDeviceInfo.manufacturer;
    brand = _androidDeviceInfo.brand;
    arch = _androidDeviceInfo.supportedAbis.first;
    simulator = !_androidDeviceInfo.isPhysicalDevice;
  } else if (_iosDeviceInfo != null) {
    name = _iosDeviceInfo.model;
    family = _iosDeviceInfo.systemName;
    arch = _iosDeviceInfo.utsname.machine;
    simulator = !_iosDeviceInfo.isPhysicalDevice;
  }

  WidgetsFlutterBinding.ensureInitialized();
  final window = WidgetsBinding.instance.window;
  return sentry.Device(
    // The values below are coming from Window.
    screenResolution: '${window.physicalSize.height.toInt()}x'
        '${window.physicalSize.width.toInt()}',
    orientation: window.physicalSize.width > window.physicalSize.height
        ? sentry.Orientation.landscape
        : sentry.Orientation.portrait,
    screenDensity: window.devicePixelRatio,
    timezone: DateTime.now().timeZoneName,
    // The values below are taken from plugins.
    name: name,
    model: model,
    manufacturer: manufacturer,
    family: family,
    brand: brand,
    simulator: simulator,
    arch: arch,
  );
}
