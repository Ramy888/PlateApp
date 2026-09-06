package com.platepatch.app

import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Play Integrity, bridged to Dart.
 *
 * The token proves this is a genuine, Play-installed build on a genuine device.
 * The server verifies it before spending anything on a model call, which is
 * what stops the Gemini budget being open to anyone with curl.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.platepatch.app/integrity"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestToken" -> requestToken(call.argument<String>("nonce"), result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestToken(nonce: String?, result: MethodChannel.Result) {
        if (nonce.isNullOrBlank()) {
            result.error("no_nonce", "A nonce is required.", null)
            return
        }
        try {
            IntegrityManagerFactory.create(applicationContext)
                .requestIntegrityToken(
                    IntegrityTokenRequest.builder().setNonce(nonce).build()
                )
                .addOnSuccessListener { response -> result.success(response.token()) }
                // Play Services missing, no network, app not installed from
                // Play — all legitimate reasons this fails on a real phone.
                // Dart turns any of them into "no token" rather than a crash.
                .addOnFailureListener { error ->
                    result.error("integrity_failed", error.message, null)
                }
        } catch (error: Exception) {
            result.error("integrity_unavailable", error.message, null)
        }
    }
}
