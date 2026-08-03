import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/native_vehicle_controller.dart';

/// One controller for the whole app: the fault provider and the console screen both reach
/// the 3D through it, and the platform view attaches its method channel to it on create.
final nativeVehicleControllerProvider = Provider<NativeVehicleController>((ref) {
  return NativeVehicleController();
});
