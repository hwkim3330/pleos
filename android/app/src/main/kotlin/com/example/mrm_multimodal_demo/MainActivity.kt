package com.example.mrm_multimodal_demo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private val control = linkedMapOf<String, Any>()

        fun readControlIntent(intent: Intent?) {
            if (intent == null || intent.getStringExtra("drivepilot_source") != "controller") return
            if (intent.hasExtra("speedKph")) control["speedKph"] = intent.getFloatExtra("speedKph", 0f)
            if (intent.hasExtra("lat")) control["lat"] = intent.getDoubleExtra("lat", 0.0)
            if (intent.hasExtra("lon")) control["lon"] = intent.getDoubleExtra("lon", 0.0)
            intent.getStringExtra("driveState")?.let { control["driveState"] = it }
            control["updatedAt"] = System.currentTimeMillis()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        readControlIntent(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mrm.pilot/pleos")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCapabilitySnapshot" -> result.success(capabilitySnapshot())
                    "getVehicleSnapshot" -> result.success(vehicleSnapshot())
                    "getControlSnapshot" -> result.success(mapOf("source" to "intent-control", "values" to control))
                    "requestRoute" -> result.success(mapOf("accepted" to true, "mode" to "demo-route"))
                    "speakStatus" -> result.success(mapOf("accepted" to true, "mode" to "demo-tts"))
                    "startVoiceCommand" -> result.success(mapOf("accepted" to true, "mode" to "demo-stt"))
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readControlIntent(intent)
    }

    private fun capabilitySnapshot(): Map<String, Any> {
        val declared = declaredPermissions()
        return mapOf(
            "source" to "android-bridge",
            "items" to listOf(
                capability("Vehicle", "declared", hasAny(declared, "CAR_INFO", "CAR_ENERGY")),
                capability("Navi", "declared", hasAny(declared, "NAVI_ROUTE", "NAVI_ROUTE_SEARCH")),
                capability("ADAS", "demo", false),
                capability("Fused", "demo", declared.contains("pleos.car.permission.FUSED_LOCATION")),
                capability("Gleo", "declared", hasAny(declared, "TTS_SERVICE", "STT_SERVICE", "LLM_SERVICE")),
                capability("Fleet", "cloud", true),
                capability("Data", "cloud", true),
            ),
        )
    }

    private fun capability(name: String, status: String, available: Boolean): Map<String, Any> {
        return mapOf("name" to name, "status" to status, "available" to available)
    }

    private fun declaredPermissions(): Set<String> {
        val info = packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
        return info.requestedPermissions?.toSet() ?: emptySet()
    }

    private fun hasAny(declared: Set<String>, vararg names: String): Boolean {
        return names.any { suffix -> declared.any { permission -> permission.endsWith(suffix) } }
    }

    private fun vehicleSnapshot(): Map<String, Any> {
        val values = linkedMapOf<String, Any?>()
        val props = linkedMapOf(
            "PERF_VEHICLE_SPEED" to 0x11600207,
            "PERF_VEHICLE_SPEED_DISPLAY" to 0x11600208,
            "PERF_ODOMETER" to 0x11600204,
            "PERF_STEERING_ANGLE" to 0x11600209,
            "GEAR_SELECTION" to 0x11400400,
            "CURRENT_GEAR" to 0x11400401,
            "IGNITION_STATE" to 0x11400409,
            "PARKING_BRAKE_ON" to 0x11200402,
            "EV_BATTERY_LEVEL" to 0x11600309,
            "EV_CHARGE_PORT_CONNECTED" to 0x1120030b,
            "EV_CHARGE_STATE" to 0x11400f41,
            "RANGE_REMAINING" to 0x11600308,
            "FUEL_LEVEL" to 0x11600307,
            "TIRE_PRESSURE" to 0x17600309,
            "ENV_OUTSIDE_TEMPERATURE" to 0x11600703,
            "TURN_SIGNAL_STATE" to 0x11400408,
            "HEADLIGHTS_STATE" to 0x11400e00,
            "HAZARD_LIGHTS_STATE" to 0x11400e03,
            "ABS_ACTIVE" to 0x1120040a,
            "TRACTION_CONTROL_ACTIVE" to 0x1120040b,
            "CRUISE_CONTROL_STATE" to 0x11401011,
            "CRUISE_CONTROL_TARGET_SPEED" to 0x11601013,
            "ADAPTIVE_CRUISE_CONTROL_LEAD_VEHICLE_MEASURED_DISTANCE" to 0x11401015,
            "LANE_KEEP_ASSIST_STATE" to 0x11401009,
            "LANE_CENTERING_ASSIST_STATE" to 0x1140100c,
            "FORWARD_COLLISION_WARNING_STATE" to 0x11401003,
            "AUTOMATIC_EMERGENCY_BRAKING_STATE" to 0x11401001,
            "HANDS_ON_DETECTION_DRIVER_STATE" to 0x11401017,
        )
        try {
            val carClass = Class.forName("android.car.Car")
            val createCar = carClass.getMethod("createCar", android.content.Context::class.java)
            val car = createCar.invoke(null, this)
            val propertyService = carClass.getField("PROPERTY_SERVICE").get(null)
            val manager = carClass.getMethod("getCarManager", String::class.java)
                .invoke(car, propertyService as String)
            val getProperty = manager.javaClass.getMethod(
                "getProperty",
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
            )
            for ((name, id) in props) {
                values[name] = runCatching {
                    val carPropertyValue = getProperty.invoke(manager, id, 0)
                    extractCarPropertyValue(carPropertyValue)
                }.getOrNull()
            }
            runCatching { carClass.getMethod("disconnect").invoke(car) }
            return mapOf("source" to "car-property", "values" to values.filterValues { it != null })
        } catch (error: Throwable) {
            return mapOf(
                "source" to "car-property-unavailable:${error.javaClass.simpleName}",
                "values" to emptyMap<String, Any>(),
            )
        }
    }

    private fun extractCarPropertyValue(carPropertyValue: Any?): Any? {
        if (carPropertyValue == null) return null
        val raw = carPropertyValue.javaClass.getMethod("getValue").invoke(carPropertyValue)
        if (raw is Boolean || raw is Number || raw is String) return raw
        if (raw is FloatArray) return raw.firstOrNull()
        if (raw is IntArray) return raw.firstOrNull()
        if (raw is LongArray) return raw.firstOrNull()
        if (raw is Array<*> && raw.isNotEmpty()) return raw.firstOrNull()
        return raw?.toString()
    }
}

class DrivePilotControlReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        MainActivity.readControlIntent(intent)
    }
}
