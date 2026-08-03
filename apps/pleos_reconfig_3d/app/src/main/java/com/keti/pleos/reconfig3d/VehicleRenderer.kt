package com.keti.pleos.reconfig3d

import android.content.Context
import android.view.Choreographer
import android.view.MotionEvent
import android.util.Base64
import android.util.Log
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
 * Renders the ROii vehicle and, more to the point, recolours the parts of it that the
 * rig can actually break.
 *
 * The asset carries no useful node names -- everything is one flat mesh list -- but its
 * *materials* are named after the architecture: `Path1`, `Path2`,
 * `connection-FrontZC-Path1-1`, `ESP_AR` and so on. So link state is applied by walking
 * the loaded asset's material instances once, bucketing them by name, and tinting the
 * buckets. Reaching into a loaded asset's materials like this is the reason to render
 * natively instead of putting a model in a WebView.
 */
class VehicleRenderer(context: Context, textureView: TextureView) {

    private companion object {
        const val TAG = "VehicleRenderer"
        const val ASSET = "roii_reconfig.glb"

        /** The textured body shell, the one node in this asset with a usable name. */
        const val BODY_ENTITY = "textured_meshobj"

        /** Material names, exact or `-` prefixed, that make up each commandable link. */
        val LINK_MATERIALS = mapOf(
            Links.PATH1 to listOf(
                "Path1",
                "connection-FrontZC-Path1-",
                "connection-Path1-RearZC-",
                "port-FrontZC-Path1-",
                "port-Path1-RearZC-",
                "ESP_AR",
            ),
            Links.PATH2 to listOf(
                "Path2",
                "connection-FrontZC-Path2-",
                "connection-Path2-RearZC-",
                "port-FrontZC-Path2-",
                "port-Path2-RearZC-",
                "ESP_BR",
            ),
            // Path 3 is the cross-link between the two front switches, driven from the
            // 7-inch's own GPIO. Only its inline board is modelled in this asset.
            Links.PATH3 to listOf("ESP_AB", "InlineESP"),
        )

        const val BASE_COLOUR = "baseColorFactor"
        val FAULT_COLOUR = floatArrayOf(1.0f, 0.20f, 0.18f, 1.0f)
        val OFFLINE_COLOUR = floatArrayOf(0.30f, 0.36f, 0.40f, 1.0f)
    }

    init {
        Utils.init()
    }

    private val modelViewer = ModelViewer(textureView)
    private val choreographer = Choreographer.getInstance()
    private val buckets = mutableMapOf<String, MutableList<MaterialInstance>>()

    /**
     * The asset's own baseColorFactor per material name, read straight out of the glTF
     * JSON. Filament's Java `MaterialInstance` exposes setters but no getters, so
     * without this a recovered link could only be restored to a guess at neutral.
     */
    private val baseColours = mutableMapOf<String, FloatArray>()
    private var appliedChannels: Map<String, String>? = null
    private var pendingState: LinkState? = null

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            choreographer.postFrameCallback(this)
            modelViewer.render(frameTimeNanos)
        }
    }

    init {
        textureView.setOnTouchListener { _, event: MotionEvent ->
            modelViewer.onTouchEvent(event)
            true
        }
        // A flat dark background rather than an environment map: the subject is the
        // vehicle's wiring, and an IBL mostly adds glare over it.
        modelViewer.scene.skybox = Skybox.Builder()
            .color(0.027f, 0.035f, 0.039f, 1.0f)
            .build(modelViewer.engine)

        // 28 mm is ModelViewer's default and frames a unit cube with a lot of air around
        // it. The vehicle is the subject of the panel, so pull in.
        modelViewer.cameraFocalLength = 45.0f
        // Filament's default exposure is a bright-daylight one (f/16, 1/125, ISO 100),
        // which renders a dark vehicle body almost black. This is an indoor bench.
        modelViewer.camera.setExposure(8.0f, 1.0f / 60.0f, 400.0f)

        addLights()
        val bytes = context.assets.open(ASSET).use { it.readBytes() }
        readBaseColours(bytes)
        loadModel(bytes)
        setShellVisible(false)
    }

    /**
     * The body shell hides everything the rig can actually break. Its material is OPAQUE
     * with a base colour texture, so unlike the WebView console there is no alpha to dial
     * down at runtime -- the shell is added to and removed from the scene instead, which
     * is cheaper anyway.
     */
    fun setShellVisible(visible: Boolean) {
        val asset = modelViewer.asset ?: return
        val body = asset.getFirstEntityByName(BODY_ENTITY)
        if (body == 0) return
        if (visible) modelViewer.scene.addEntity(body) else modelViewer.scene.removeEntity(body)
        shellVisible = visible
    }

    var shellVisible: Boolean = true
        private set

    private fun addLights() {
        val engine = modelViewer.engine
        // Key and fill. With no IBL a single directional light leaves half the vehicle
        // unreadably black, and the parts that matter sit low on the body.
        val key = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(1.0f, 0.98f, 0.95f)
            .intensity(120_000.0f)
            .direction(-0.35f, -1.0f, -0.45f)
            .castShadows(false)
            .build(engine, key)
        modelViewer.scene.addEntity(key)

        val fill = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(0.85f, 0.92f, 1.0f)
            .intensity(60_000.0f)
            .direction(0.6f, 0.35f, 0.7f)
            .castShadows(false)
            .build(engine, fill)
        modelViewer.scene.addEntity(fill)
    }

    private fun readBaseColours(bytes: ByteArray) {
        // The file is glTF JSON despite its .glb extension, which makes this a plain
        // parse rather than chunk walking.
        if (bytes.isEmpty() || bytes[0] != '{'.code.toByte()) return
        runCatching {
            val materials = JSONObject(String(bytes)).optJSONArray("materials") ?: return
            for (i in 0 until materials.length()) {
                val material = materials.optJSONObject(i) ?: continue
                val name = material.optString("name").takeIf { it.isNotEmpty() } ?: continue
                val factor = material.optJSONObject("pbrMetallicRoughness")
                    ?.optJSONArray("baseColorFactor") ?: continue
                val colour = FloatArray(4) { index ->
                    if (index < factor.length()) factor.optDouble(index, 1.0).toFloat() else 1.0f
                }
                baseColours[name] = colour
            }
        }
    }

    private fun loadModel(bytes: ByteArray) {
        val buffer = ByteBuffer.allocateDirect(bytes.size).apply {
            put(bytes)
            rewind()
        }
        // The resource callback has to answer for every URI the asset declares, and
        // returning null for even one makes ModelViewer throw the whole asset away and
        // leave a silently empty scene -- which looks exactly like a compositing bug.
        // This asset's buffer and both images are embedded base64, so they are decoded
        // here rather than fetched.
        modelViewer.loadModelGltf(buffer) { uri -> decodeDataUri(uri) }
        modelViewer.transformToUnitCube()
        indexMaterials()
        // Loading failures in gltfio are quiet, and an empty viewport looks exactly like
        // a compositing problem, so the counts go to logcat once.
        val asset = modelViewer.asset
        Log.i(
            TAG,
            "model loaded: entities=${asset?.entities?.size ?: 0} " +
                "renderables=${asset?.renderableEntities?.size ?: 0} " +
                "materials=${asset?.instance?.materialInstances?.size ?: 0} " +
                "linkBuckets=${buckets.mapValues { it.value.size }}",
        )
    }

    /** Decodes a `data:<mime>;base64,<payload>` URI into the direct buffer gltfio wants. */
    private fun decodeDataUri(uri: String): ByteBuffer? {
        val marker = "base64,"
        val start = uri.indexOf(marker)
        if (!uri.startsWith("data:") || start < 0) {
            Log.w(TAG, "resource is not an embedded base64 URI: ${uri.take(48)}")
            return null
        }
        val decoded = runCatching {
            Base64.decode(uri.substring(start + marker.length), Base64.DEFAULT)
        }.getOrNull()
        if (decoded == null) {
            Log.w(TAG, "failed to decode embedded resource")
            return null
        }
        return ByteBuffer.allocateDirect(decoded.size).apply {
            put(decoded)
            rewind()
        }
    }

    private fun indexMaterials() {
        // Material instances hang off the asset's *instance*, not the asset.
        val asset = modelViewer.asset?.instance ?: return
        for (instance in asset.materialInstances) {
            val name = instance.name ?: continue
            val channel = LINK_MATERIALS.entries.firstOrNull { (_, names) ->
                names.any { if (it.endsWith("-")) name.startsWith(it) else name == it }
            }?.key ?: continue
            buckets.getOrPut(channel) { mutableListOf() }.add(instance)
        }
        pendingState?.let { apply(it) }
    }

    fun apply(state: LinkState) {
        if (buckets.isEmpty()) {
            // Materials are not indexed until the asset is loaded; keep the newest state
            // so the first frame after load is already correct.
            pendingState = state
            return
        }
        // Repaint only on a real change: this runs from a state flow that also ticks for
        // heartbeats and sequence numbers.
        if (state.channels == appliedChannels && state.gatewayOnline) return
        appliedChannels = state.channels
        for ((channel, instances) in buckets) {
            val colourFor: (String) -> FloatArray = when {
                !state.gatewayOnline -> { _ -> OFFLINE_COLOUR }
                state.linkHealthy(channel) -> { name ->
                    baseColours[name] ?: floatArrayOf(1f, 1f, 1f, 1f)
                }
                else -> { _ -> FAULT_COLOUR }
            }
            for (instance in instances) {
                // Asked rather than assumed: setParameter on a shader without that
                // parameter aborts in native code, which would take the app down instead
                // of throwing something catchable.
                if (!instance.material.hasParameter(BASE_COLOUR)) continue
                val colour = colourFor(instance.name ?: "")
                instance.setParameter(
                    BASE_COLOUR,
                    colour[0],
                    colour[1],
                    colour[2],
                    colour.getOrElse(3) { 1f },
                )
            }
        }
    }

    fun resume() = choreographer.postFrameCallback(frameCallback)

    fun pause() = choreographer.removeFrameCallback(frameCallback)

    fun destroy() {
        choreographer.removeFrameCallback(frameCallback)
        modelViewer.destroyModel()
    }
}
