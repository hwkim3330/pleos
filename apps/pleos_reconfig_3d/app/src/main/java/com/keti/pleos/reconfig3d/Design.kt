package com.keti.pleos.reconfig3d

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * One dark instrument palette, four semantic colours. Colour is reserved for state so
 * everything structural stays neutral, which is what keeps a screen this dense readable.
 */
object Tone {
    val background = Color(0xFF07090A)
    val surface = Color(0xFF11161B)
    val surfaceRaised = Color(0xFF171F26)
    val hairline = Color(0xFF222C34)

    val textPrimary = Color(0xFFE8EEF3)
    val textSecondary = Color(0xFF8C9BA8)
    val textFaint = Color(0xFF5A6874)

    val healthy = Color(0xFF3ED598)
    val warning = Color(0xFFFFB84D)
    val fault = Color(0xFFFF5E5B)
    val idle = Color(0xFF44535F)
}

/** Labels small, uppercase and wide; values large and tight. That contrast is the hierarchy. */
object Face {
    val label = TextStyle(
        fontSize = 11.sp,
        letterSpacing = 1.4.sp,
        fontWeight = FontWeight.SemiBold,
        color = Tone.textFaint,
    )
    val value = TextStyle(
        fontSize = 15.sp,
        letterSpacing = (-0.1).sp,
        fontWeight = FontWeight.SemiBold,
        color = Tone.textPrimary,
    )
    val headline = TextStyle(
        fontSize = 34.sp,
        letterSpacing = (-1).sp,
        fontWeight = FontWeight.Bold,
        color = Tone.textPrimary,
    )
    val body = TextStyle(fontSize = 13.sp, color = Tone.textSecondary)
    val mono = TextStyle(fontSize = 12.sp, letterSpacing = 0.2.sp, color = Tone.textSecondary)
}
