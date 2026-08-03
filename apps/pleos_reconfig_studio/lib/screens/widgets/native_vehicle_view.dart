import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/native_vehicle_provider.dart';

/// The vehicle, rendered by Filament in the Android host instead of by model-viewer in a
/// WebView.
///
/// Measured on the tablet before the swap: the WebView path cost 521 MB PSS plus a
/// separate 183 MB Chromium process, and its 90th-percentile frame was 150 ms. Filament
/// in-process was 231 MB and 25 ms. Dart was never the cost.
///
/// The widget is a thin shell: it owns the platform view and forwards state changes, and
/// deliberately holds no 3D state of its own so there is one source of truth.
class NativeVehicleView extends ConsumerStatefulWidget {
  const NativeVehicleView({
    super.key,
    required this.channels,
    required this.shellOpacity,
    this.resetSignal = 0,
  });

  /// Channel id to health word, straight from the controller.
  final Map<String, String> channels;

  /// 0 removes the body shell from the scene, 1 is fully opaque.
  final double shellOpacity;

  /// Bumping this asks the host to reframe the model; a value rather than a callback so a
  /// rebuild cannot lose the request.
  final int resetSignal;

  @override
  ConsumerState<NativeVehicleView> createState() => _NativeVehicleViewState();
}

class _NativeVehicleViewState extends ConsumerState<NativeVehicleView> {
  static const _viewType = 'pleos.reconfig/vehicle';

  MethodChannel? _channel;
  int _appliedReset = 0;

  @override
  void didUpdateWidget(NativeVehicleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final channel = _channel;
    if (channel == null) return;
    if (!mapEquals(oldWidget.channels, widget.channels)) {
      channel.invokeMethod('setChannels', widget.channels);
    }
    if (oldWidget.shellOpacity != widget.shellOpacity) {
      channel.invokeMethod('setShellOpacity', widget.shellOpacity);
    }
    if (widget.resetSignal != _appliedReset) {
      _appliedReset = widget.resetSignal;
      channel.invokeMethod('resetCamera');
    }
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('$_viewType/$id');
    _channel = channel;
    _appliedReset = widget.resetSignal;
    // The fault provider also drives the 3D, so the channel is shared through the
    // controller rather than kept private to this widget.
    ref.read(nativeVehicleControllerProvider).attach(channel);
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) {
      ref.read(nativeVehicleControllerProvider).detach(channel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      // Nothing to fall back to: the renderer lives in the Android host. Say so rather
      // than showing an empty rectangle that reads as a broken viewer.
      return const ColoredBox(
        color: Color(0xFFF2F4F7),
        child: Center(
          child: Text(
            'The 3D vehicle is rendered by the Android host',
            style: TextStyle(color: Color(0xFF7A8590)),
          ),
        ),
      );
    }
    // Hybrid composition, so the platform view sits inside the widget tree and the panels
    // above it keep drawing over it. Virtual displays would cost an extra copy per frame
    // and break the touch handling the camera manipulator needs.
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      ),
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: <String, Object?>{
            'channels': widget.channels,
            'shellOpacity': widget.shellOpacity,
          },
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        );
        controller
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..addOnPlatformViewCreatedListener(_onPlatformViewCreated)
          ..create();
        return controller;
      },
    );
  }
}
