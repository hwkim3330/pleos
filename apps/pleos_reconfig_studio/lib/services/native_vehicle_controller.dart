import 'package:flutter/services.dart';

/// Talks to the Filament vehicle in the Android host.
///
/// This replaces `ViewerService`, which drove the same features by injecting JavaScript
/// into a WebView. The shape is kept deliberately similar so the fault provider did not
/// have to be restructured: it still reaches the 3D through a provider, the provider just
/// speaks a method channel now.
///
/// Every call is a no-op until the platform view attaches. That is the normal case for the
/// first frames, and silently dropping those is right: the view is handed the current state
/// as creation parameters, so nothing is lost.
class NativeVehicleController {
  MethodChannel? _channel;

  void attach(MethodChannel channel) => _channel = channel;

  void detach(MethodChannel channel) {
    if (_channel == channel) _channel = null;
  }

  bool get isAttached => _channel != null;

  /// Channel id to health word, exactly as the controller reports it.
  void setChannels(Map<String, String> channels) =>
      _channel?.invokeMethod('setChannels', channels);

  /// 0 removes the body shell from the scene, 1 is fully opaque.
  void setShellOpacity(double opacity) =>
      _channel?.invokeMethod('setShellOpacity', opacity);

  void resetCamera() => _channel?.invokeMethod('resetCamera');

  /// Alert target (`Path1Route`, `FrontSwitchA`, `FrontCenterLidar`, ...) to severity.
  /// The host owns the target-to-material mapping, so a target it does not know is
  /// ignored rather than silently tinting the wrong part.
  void setAlerts(Map<String, int> alerts) =>
      _channel?.invokeMethod('setAlerts', alerts);

  void clearAlerts() => _channel?.invokeMethod('setAlerts', <String, int>{});
}
