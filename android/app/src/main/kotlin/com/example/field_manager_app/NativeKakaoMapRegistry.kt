package com.example.field_manager_app.v2

import android.util.Log

object NativeKakaoMapRegistry {
    const val LOG_TAG = "FIELD_NATIVE_MAP"

    private val views = linkedSetOf<NativeKakaoMapPlatformView>()
    private var pendingMarkers: List<NativeMarkerDto>? = null

    fun register(view: NativeKakaoMapPlatformView) {
        views.add(view)
        pendingMarkers?.let { view.renderMarkers(it) }
    }

    fun unregister(view: NativeKakaoMapPlatformView) {
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

    fun renderMarkers(arguments: Any?) {
        val markers = NativeMarkerDto.fromFlutterList(arguments)
        if (views.isEmpty()) {
            pendingMarkers = markers
            Log.d(LOG_TAG, "renderMarkers received before PlatformView registration: total=${markers.size}")
            return
        }

        pendingMarkers = null
        views.forEach { view -> view.renderMarkers(markers) }
    }

    fun clearMarkers() {
        pendingMarkers = emptyList()
        views.forEach { view -> view.clearMarkers() }
    }
}
