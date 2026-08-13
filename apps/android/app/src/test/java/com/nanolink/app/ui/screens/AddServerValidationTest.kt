package com.nanolink.app.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AddServerValidationTest {
    @Test
    fun normalizesWhitespaceAndTrailingSlash() {
        assertEquals(
            "https://ops.example.com/nano",
            normalizedServerUrl("  https://ops.example.com/nano/  ", forceTls = false),
        )
    }

    @Test
    fun forceTlsUpgradesOnlyTheScheme() {
        assertEquals(
            "https://192.168.1.20:8080",
            normalizedServerUrl("http://192.168.1.20:8080", forceTls = true),
        )
    }

    @Test
    fun rejectsMissingSchemeAndUnsupportedSchemes() {
        assertNull(normalizedServerUrl("ops.example.com", forceTls = false))
        assertNull(normalizedServerUrl("ftp://ops.example.com", forceTls = false))
    }

    @Test
    fun rejectsCredentialsQueryAndFragment() {
        assertNull(normalizedServerUrl("https://user:pass@ops.example.com", forceTls = false))
        assertNull(normalizedServerUrl("https://ops.example.com?token=secret", forceTls = false))
        assertNull(normalizedServerUrl("https://ops.example.com/#section", forceTls = false))
    }
}
