package com.keti.pleos.reconfig3d

/** Channel ids as the controller names them, in the order the rig numbers the paths. */
object Links {
    const val PATH1 = "tsn_front_a"
    const val PATH2 = "tsn_front_b"
    const val PATH3 = "tsn_rear"
    val all = listOf(PATH1, PATH2, PATH3)

    fun label(channel: String) = when (channel) {
        PATH1 -> "Path 1"
        PATH2 -> "Path 2"
        PATH3 -> "Path 3"
        else -> channel
    }
}

/**
 * Everything the tablet knows about the rig, all of it off the wire. Nothing here is
 * simulated: a console that mixes real and invented values cannot be trusted during
 * a fault, which is the only time it matters.
 */
data class LinkState(
    val gatewayOnline: Boolean = false,
    val mode: String = "--",
    val sequence: Int = 0,
    val ioNodeOnline: Boolean = false,
    val channels: Map<String, String> = emptyMap(),
    val pathNodesOnline: Map<String, Boolean> = emptyMap(),
) {
    fun linkHealthy(channel: String) = (channels[channel] ?: "NORMAL") == "NORMAL"

    val faultedLinks: List<String> get() = Links.all.filterNot { linkHealthy(it) }

    val isFaulted: Boolean get() = faultedLinks.isNotEmpty()

    /**
     * Path 3 has no display node — the 7-inch drives that relay from its own GPIO —
     * so its liveness is the gateway's own.
     */
    fun pathNodeOnline(path: Int) =
        if (path == 3) gatewayOnline else pathNodesOnline[path.toString()] == true
}

enum class EntryKind { LINK, FAULT, RECOVERY, COMMAND, PROBLEM }

data class LogEntry(
    val atMillis: Long,
    val kind: EntryKind,
    val title: String,
    val detail: String = "",
)
