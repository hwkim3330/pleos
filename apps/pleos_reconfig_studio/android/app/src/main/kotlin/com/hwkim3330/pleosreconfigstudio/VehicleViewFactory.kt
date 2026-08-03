package com.hwkim3330.pleosreconfigstudio

import android.content.Context
import android.view.TextureView
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Hosts the Filament vehicle as a Flutter platform view, so the light console keeps its
 * layout and only the renderer changes.
 *
 * A `TextureView` rather than a `SurfaceView`: Flutter's hybrid composition draws the
 * platform view into the widget tree, and a SurfaceView would be composited below the
 * window where the Flutter background paints over it.
 */
class VehicleViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    companion object {
        const val VIEW_TYPE = "pleos.reconfig/vehicle"
    }

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return VehicleView(context, viewId, messenger, args as? Map<*, *>)
    }
}

private class VehicleView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    args: Map<*, *>?,
) : PlatformView, MethodChannel.MethodCallHandler {

    private val textureView = TextureView(context)
    private val renderer = VehicleRenderer(context, textureView)
    private val channel =
        MethodChannel(messenger, "${VehicleViewFactory.VIEW_TYPE}/$viewId").also {
            it.setMethodCallHandler(this)
        }

    init {
        // Creation args carry the first state, so the model is never shown with stale or
        // default link colours between attach and the first update.
        (args?.get("channels") as? Map<*, *>)?.let { renderer.applyChannels(it.toChannelMap()) }
        (args?.get("shellOpacity") as? Number)?.let { renderer.setShellOpacity(it.toFloat()) }
    }

    override fun getView(): View = textureView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setChannels" -> {
                val channels = (call.arguments as? Map<*, *>)?.toChannelMap() ?: emptyMap()
                renderer.applyChannels(channels)
                result.success(null)
            }
            "setAlerts" -> {
                val alerts = (call.arguments as? Map<*, *>)?.entries
                    ?.mapNotNull { (key, value) ->
                        val target = key as? String ?: return@mapNotNull null
                        val severity = (value as? Number)?.toInt() ?: return@mapNotNull null
                        target to severity
                    }?.toMap() ?: emptyMap()
                renderer.applyAlerts(alerts)
                result.success(null)
            }
            "setShellOpacity" -> {
                renderer.setShellOpacity((call.arguments as? Number)?.toFloat() ?: 1f)
                result.success(null)
            }
            "resetCamera" -> {
                renderer.resetCamera()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
        renderer.destroy()
    }
}

private fun Map<*, *>.toChannelMap(): Map<String, String> =
    entries.mapNotNull { (key, value) ->
        val id = key as? String ?: return@mapNotNull null
        val health = value as? String ?: return@mapNotNull null
        id to health
    }.toMap()
