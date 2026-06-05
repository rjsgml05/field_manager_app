package com.example.field_manager_app.v2

import android.util.Log
import com.kakao.vectormap.MapView

object NativeKakaoMapRegistry {
    const val LOG_TAG = "FIELD_NATIVE_MAP"

    private val views = linkedSetOf<MapView>()

    fun register(view: MapView) {
        views.add(view)
    }

    fun unregister(view: MapView) {
        views.remove(view)
    }

    fun resumeAll() {
        views.forEach { view ->
            runCatching { view.resume() }
                .onFailure { Log.w(LOG_TAG, "MapView resume failed.", it) }
        }
    }

    fun pauseAll() {
        views.forEach { view ->
            runCatching { view.pause() }
                .onFailure { Log.w(LOG_TAG, "MapView pause failed.", it) }
        }
    }

    fun finishAll() {
        views.toList().forEach { view ->
            runCatching { view.finish() }
                .onFailure { Log.w(LOG_TAG, "MapView finish failed.", it) }
        }
        views.clear()
    }
}
