package com.hwkim3330.pleosreconfigstudio

import android.content.Context
import android.util.Log
import android.view.Choreographer
import android.view.MotionEvent
import android.view.TextureView
import com.google.android.filament.EntityManager
import com.google.android.filament.LightManager
import com.google.android.filament.MaterialInstance
import com.google.android.filament.Skybox
import com.google.android.filament.utils.ModelViewer
import com.google.android.filament.utils.Utils
import org.json.JSONObject
import java.nio.ByteBuffer

/**
 * Renders the ROii vehicle with Filament, replacing the WebView that used to host
 * model-viewer.
 *
 * Measured on the tablet before the swap: the WebView path cost 521 MB PSS plus a
 * separate 183 MB Chromium process, with a 150 ms 90th-percentile frame time. Filament
 * in-process was 231 MB and 25 ms. The renderer is the whole reason for the difference;
 * Dart was never the problem.
 *
 * Link state is applied by material name. The asset has no usable node names -- it is one
 * flat mesh list -- but its materials are named after the architecture (`Path1`,
 * `connection-FrontZC-Path1-1`, `ESP_AR`, ...), so each commandable link resolves to a
 * bucket of material instances that can be tinted.
 */
class VehicleRenderer(context: Context, textureView: TextureView) {

    private companion object {
        const val TAG = "VehicleRenderer"
        const val ASSET = "roii_reconfig.glb"

        /** The textured body shell: the one node in this asset with a usable name. */
        const val BODY_ENTITY = "textured_meshobj"
        const val BODY_MATERIAL = "roii"

        /** Material names, exact or `-` prefixed, that make up each commandable link. */
        val LINK_MATERIALS = mapOf(
            "tsn_front_a" to listOf(
                "Path1",
                "connection-FrontZC-Path1-",
                "connection-Path1-RearZC-",
                "port-FrontZC-Path1-",
                "port-Path1-RearZC-",
                "ESP_AR",
            ),
            "tsn_front_b" to listOf(
                "Path2",
                "connection-FrontZC-Path2-",
                "connection-Path2-RearZC-",
                "port-FrontZC-Path2-",
                "port-Path2-RearZC-",
                "ESP_BR",
            ),
            // Path 3 is the cross-link between the two front switches, driven from the
            // 7-inch's own GPIO. Only its inline board is modelled here.
            "tsn_rear" to listOf("ESP_AB", "InlineESP"),
        )

        /**
         * Alert targets the app can raise, mapped to the materials that make them up.
         * Mirrors `alertMaterialGroups` in the Dart constants, which the WebView used for
         * the same purpose. A target that is not listed falls back to a material of the
         * same name -- most sensor targets are named exactly like their material.
         */
        val ALERT_GROUPS = mapOf(
            "Path1Route" to listOf(
                "connection-FrontZC-Path1-",
                "Path1",
                "connection-Path1-RearZC-",
            ),
            "Path2Route" to listOf(
                "connection-FrontZC-Path2-",
                "Path2",
                "connection-Path2-RearZC-",
            ),
            "Path3Route" to listOf("ESP_AB", "InlineESP"),
            "FrontSwitchA" to listOf("FrontZC"),
            "FrontSwitchB" to listOf("FrontZC"),
            "RearSwitch" to listOf("RearZC"),
        )

        const val BASE_COLOUR = "baseColorFactor"
        val FAULT_COLOUR = floatArrayOf(1.0f, 0.18f, 0.16f, 1.0f)

        /** Severity 1 is a warning, 2 and above is a fault. */
        val WARNING_COLOUR = floatArrayOf(1.0f, 0.66f, 0.13f, 1.0f)
    }

    init {
        Utils.init()
    }

    private val modelViewer = ModelViewer(textureView)
    private val choreographer = Choreographer.getInstance()
    private val buckets = mutableMapOf<String, MutableList<MaterialInstance>>()
    private var bodyMaterial: MaterialInstance? = null

    /**
     * Each material's own baseColorFactor, read straight out of the glTF JSON. Filament's
     * Java `MaterialInstance` has setters but no getters, so without this a recovered link
     * could only be restored to a guess at neutral rather than to what the model ships
     * with.
     */
    private val baseColours = mutableMapOf<String, FloatArray>()
    private var appliedChannels: Map<String, String> = emptyMap()
    private var appliedAlerts: Map<String, Int> = emptyMap()

    /** Every material an alert has ever tinted, so clearing one can restore it. */
    private val alertableNames = mutableSetOf<String>()
    private var appliedShell = -1.0f
    private var pendingChannels: Map<String, String>? = null
    private var pendingShell: Float? = null

    /**
     * Rendering is on demand. A Choreographer callback posted unconditionally every frame
     * held one core at ~55% on a scene that only changes when someone drags it, which was
     * the one place the native viewer looked worse than the WebView.
     */
    private var frameRequested = false
    private var dirty = true

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            frameRequested = false
            modelViewer.render(frameTimeNanos)
            // gltfio streams renderables into the scene across several frames, and the
            // camera manipulator settles over a few more, so keep drawing while either is
            // still in motion.
            if (dirty) {
                dirty = false
                requestFrame()
            }
        }
    }

    private fun requestFrame() {
        if (frameRequested) return
        frameRequested = true
        choreographer.postFrameCallback(frameCallback)
    }

    private fun invalidate() {
        dirty = true
        requestFrame()
    }

    init {
        textureView.setOnTouchListener { _, event: MotionEvent ->
            modelViewer.onTouchEvent(event)
            // A drag moves the camera over several frames, so keep the loop alive until it
            // settles rather than drawing one frame per touch event.
            invalidate()
            true
        }
        // A flat background that matches the Flutter surface behind it, so the panel does
        // not show a seam where the texture starts.
        modelViewer.scene.skybox = Skybox.Builder()
            .color(0.949f, 0.957f, 0.969f, 1.0f)
            .build(modelViewer.engine)
        modelViewer.cameraFocalLength = 40.0f

        addLights()
        val bytes = context.assets.open(ASSET).use { it.readBytes() }
        readBaseColours(bytes)
        loadModel(bytes)
        indexMaterials()
        pendingChannels?.let { applyChannels(it) }
        pendingShell?.let { setShellOpacity(it) }
        invalidate()
    }

    private fun addLights() {
        val engine = modelViewer.engine
        // Key and fill. With no IBL a single directional light leaves half the vehicle
        // unreadable, and the parts that matter sit low on the body.
        val key = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(1.0f, 0.99f, 0.97f)
            .intensity(110_000.0f)
            .direction(-0.35f, -1.0f, -0.45f)
            .castShadows(false)
            .build(engine, key)
        modelViewer.scene.addEntity(key)

        val fill = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(0.88f, 0.93f, 1.0f)
            .intensity(55_000.0f)
            .direction(0.6f, 0.35f, 0.7f)
            .castShadows(false)
            .build(engine, fill)
        modelViewer.scene.addEntity(fill)
    }

    private fun loadModel(bytes: ByteArray) {
        val buffer = ByteBuffer.allocateDirect(bytes.size).apply {
            put(bytes)
            rewind()
        }
        // A real binary glb, repacked by tools/build_native_vehicle_asset.py. The Flutter
        // asset is glTF JSON with base64 data URIs, which would force every resource
        // through the callback below.
        modelViewer.loadModelGlb(buffer)
        modelViewer.transformToUnitCube()
        orientModel()
        val asset = modelViewer.asset
        Log.i(
            TAG,
            "model loaded: entities=${asset?.entities?.size ?: 0} " +
                "renderables=${asset?.renderableEntities?.size ?: 0} " +
                "materials=${asset?.instance?.materialInstances?.size ?: 0}",
        )
    }

    /**
     * Turns the model to the three-quarter view the WebView opened with (`45deg 65deg`).
     *
     * Done by rotating the model rather than by building a custom camera manipulator: a
     * manipulator has to be constructed with a viewport, and giving it a placeholder left
     * the projection wrong and the vehicle off-screen. Rotating the root needs no camera
     * plumbing and leaves ModelViewer's own framing, which is already correct, alone.
     */
    private fun orientModel() {
        val asset = modelViewer.asset ?: return
        val transforms = modelViewer.engine.transformManager
        val instance = transforms.getInstance(asset.root)
        if (instance == 0) return
        val current = FloatArray(16)
        transforms.getTransform(instance, current)
        transforms.setTransform(instance, multiply(current, yaw(-35f, -18f)))
    }

    /** Column-major yaw-then-pitch, spelled out so it does not depend on a math helper. */
    private fun yaw(yawDegrees: Float, pitchDegrees: Float): FloatArray {
        val y = Math.toRadians(yawDegrees.toDouble())
        val x = Math.toRadians(pitchDegrees.toDouble())
        val cy = Math.cos(y).toFloat()
        val sy = Math.sin(y).toFloat()
        val cx = Math.cos(x).toFloat()
        val sx = Math.sin(x).toFloat()
        // Ry * Rx
        return floatArrayOf(
            cy, sy * sx, -sy * cx, 0f,
            0f, cx, sx, 0f,
            sy, -cy * sx, cy * cx, 0f,
            0f, 0f, 0f, 1f,
        )
    }

    private fun multiply(a: FloatArray, b: FloatArray): FloatArray {
        val out = FloatArray(16)
        for (column in 0 until 4) {
            for (row in 0 until 4) {
                var sum = 0f
                for (k in 0 until 4) {
                    sum += a[k * 4 + row] * b[column * 4 + k]
                }
                out[column * 4 + row] = sum
            }
        }
        return out
    }

    /**
     * Pulls every material's baseColorFactor out of the glb's own JSON chunk: 12 byte
     * header, then a length/type pair, then the JSON. Cheaper and more honest than keeping
     * a hand-maintained table of colours in sync with the asset.
     */
    private fun readBaseColours(bytes: ByteArray) {
        runCatching {
            val buffer = ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN)
            buffer.position(12)
            val length = buffer.int
            buffer.int // chunk type; the JSON chunk is always first in a valid glb
            val json = String(bytes, 20, length, Charsets.UTF_8).trim { it <= ' ' }
            val materials = JSONObject(json).optJSONArray("materials") ?: return
            for (i in 0 until materials.length()) {
                val material = materials.optJSONObject(i) ?: continue
                val name = material.optString("name").takeIf { it.isNotEmpty() } ?: continue
                val factor = material.optJSONObject("pbrMetallicRoughness")
                    ?.optJSONArray("baseColorFactor") ?: continue
                baseColours[name] = FloatArray(4) { index ->
                    if (index < factor.length()) factor.optDouble(index, 1.0).toFloat() else 1.0f
                }
            }
        }.onFailure { Log.w(TAG, "could not read base colours from the glb: $it") }
    }

    private fun indexMaterials() {
        // Material instances hang off the asset's *instance*, not the asset.
        val instance = modelViewer.asset?.instance ?: return
        for (material in instance.materialInstances) {
            val name = material.name ?: continue
            if (name == BODY_MATERIAL) bodyMaterial = material
            val channel = LINK_MATERIALS.entries.firstOrNull { (_, names) ->
                names.any { if (it.endsWith("-")) name.startsWith(it) else name == it }
            }?.key ?: continue
            buckets.getOrPut(channel) { mutableListOf() }.add(material)
        }
    }

    /** Health per channel id, exactly as the controller reports it. */
    fun applyChannels(channels: Map<String, String>) {
        if (buckets.isEmpty()) {
            pendingChannels = channels
            return
        }
        if (channels == appliedChannels) return
        appliedChannels = channels
        for ((channel, materials) in buckets) {
            val faulted = (channels[channel] ?: "NORMAL") != "NORMAL"
            for (material in materials) {
                if (!material.material.hasParameter(BASE_COLOUR)) continue
                val colour = if (faulted) {
                    FAULT_COLOUR
                } else {
                    baseColours[material.name ?: ""] ?: floatArrayOf(1f, 1f, 1f, 1f)
                }
                material.setParameter(
                    BASE_COLOUR,
                    colour[0],
                    colour[1],
                    colour[2],
                    colour.getOrElse(3) { 1f },
                )
            }
        }
        invalidate()
    }

    /**
     * Alert target to severity, as the fault provider holds it. The whole set is sent every
     * time, so this is the one place that decides what is tinted and nothing can drift.
     */
    fun applyAlerts(alerts: Map<String, Int>) {
        if (alerts == appliedAlerts) return
        appliedAlerts = alerts
        // Repaint everything the alerts could touch, then the link state on top: a link the
        // controller reports as faulted outranks a simulated alert on the same material.
        val instance = modelViewer.asset?.instance ?: return
        val alerted = mutableMapOf<MaterialInstance, FloatArray>()
        for ((target, severity) in alerts) {
            val names = ALERT_GROUPS[target] ?: listOf(target)
            val colour = if (severity >= 2) FAULT_COLOUR else WARNING_COLOUR
            for (material in instance.materialInstances) {
                val name = material.name ?: continue
                val matches = names.any {
                    if (it.endsWith("-")) name.startsWith(it) else name == it
                }
                if (matches) alerted[material] = colour
            }
        }
        for (material in instance.materialInstances) {
            if (!material.material.hasParameter(BASE_COLOUR)) continue
            val name = material.name ?: continue
            // Only touch materials that are alerting now or were alerting before, so this
            // never fights setShellOpacity or the link paint over unrelated parts.
            val colour = alerted[material]
                ?: if (name in alertableNames) {
                    baseColours[name] ?: floatArrayOf(1f, 1f, 1f, 1f)
                } else {
                    continue
                }
            material.setParameter(
                BASE_COLOUR,
                colour[0],
                colour[1],
                colour[2],
                colour.getOrElse(3) { 1f },
            )
        }
        alertableNames.addAll(alerted.keys.mapNotNull { it.name })
        // Link state is authoritative, so re-assert it over anything just repainted.
        val channels = appliedChannels
        appliedChannels = emptyMap()
        applyChannels(channels)
        invalidate()
    }

    /**
     * 0 hides the body entirely, 1 is fully opaque. Real alpha only works because
     * `tools/build_native_vehicle_asset.py` sets this material to alphaMode BLEND —
     * gltfio bakes blending into the variant it picks and `MaterialInstance` cannot change
     * it later, so on the unpatched asset this call is silently ignored.
     */
    fun setShellOpacity(opacity: Float) {
        val clamped = opacity.coerceIn(0f, 1f)
        if (clamped == appliedShell) return
        val body = bodyMaterial
        if (body == null) {
            pendingShell = clamped
            return
        }
        appliedShell = clamped
        val entity = modelViewer.asset?.getFirstEntityByName(BODY_ENTITY) ?: 0
        if (entity != 0) {
            // Below a couple of percent, blending still costs a full-screen transparent
            // pass for nothing visible, so drop the renderable out of the scene instead.
            if (clamped <= 0.02f) {
                modelViewer.scene.removeEntity(entity)
            } else {
                modelViewer.scene.addEntity(entity)
            }
        }
        if (body.material.hasParameter(BASE_COLOUR)) {
            val base = baseColours[BODY_MATERIAL] ?: floatArrayOf(1f, 1f, 1f, 1f)
            body.setParameter(BASE_COLOUR, base[0], base[1], base[2], clamped)
        }
        invalidate()
    }

    fun resetCamera() {
        modelViewer.transformToUnitCube()
        orientModel()
        invalidate()
    }

    fun resume() = invalidate()

    fun pause() {
        choreographer.removeFrameCallback(frameCallback)
        frameRequested = false
    }

    fun destroy() {
        pause()
        modelViewer.destroyModel()
    }
}
