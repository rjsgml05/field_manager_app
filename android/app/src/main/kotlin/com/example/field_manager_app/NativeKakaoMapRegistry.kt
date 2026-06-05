package com.example.field_manager_app.v2

import android.util.Log
import io.flutter.plugin.common.MethodChannel

object NativeKakaoMapRegistry {
    const val LOG_TAG = "FIELD_NATIVE_MAP"

    private val views = linkedSetOf<NativeKakaoMapPlatformView>()
    private var eventChannel: MethodChannel? = null
    private var pendingMarkers: List<NativeMarkerDto>? = null
    private var pendingLines: List<NativeLineDto>? = null
    private var pendingGpsLocation: NativeGpsLocation? = null
    private var pendingShowAllLineLabels: Boolean = false
    private var pendingMarkerMoveMode: Boolean = false

    fun register(view: NativeKakaoMapPlatformView) {
        views.add(view)
        pendingMarkers?.let { view.renderMarkers(it) }
        pendingLines?.let { view.renderLines(it) }
        view.setShowAllLineLabels(pendingShowAllLineLabels)
        view.setMarkerMoveMode(pendingMarkerMoveMode)
        pendingGpsLocation?.let { view.showCurrentLocation(it) }
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

    fun setEventChannel(channel: MethodChannel) {
        eventChannel = channel
    }

    fun sendMapReady() {
        eventChannel?.invokeMethod("mapReady", null)
    }

    fun sendMarkerTap(marker: NativeMarkerDto) {
        eventChannel?.invokeMethod("markerTap", marker.toEventMap())
    }

    fun sendMapTap(lat: Double, lng: Double) {
        eventChannel?.invokeMethod(
            "mapTap",
            mapOf(
                "event" to "mapTap",
                "lat" to lat,
                "lng" to lng
            )
        )
    }

    fun sendMarkerDragEnd(marker: NativeMarkerDto, lat: Double, lng: Double) {
        eventChannel?.invokeMethod("markerDragEnd", marker.toDragEndEventMap(lat, lng))
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

    fun renderLines(arguments: Any?) {
        val lines = NativeLineDto.fromFlutterList(arguments)
        if (views.isEmpty()) {
            pendingLines = lines
            Log.d(LOG_TAG, "renderLines received before PlatformView registration: total=${lines.size}")
            return
        }

        pendingLines = null
        views.forEach { view -> view.renderLines(lines) }
    }

    fun moveTo(arguments: Any?) {
        val location = NativeGpsLocation.fromFlutterMap(arguments, defaultMoveCamera = true) ?: return
        views.forEach { view -> view.moveTo(location.lat, location.lng, location.level ?: 15) }
    }

    fun showCurrentLocation(arguments: Any?) {
        val location = NativeGpsLocation.fromFlutterMap(arguments, defaultMoveCamera = false) ?: return
        pendingGpsLocation = location
        views.forEach { view -> view.showCurrentLocation(location) }
    }

    fun clearCurrentLocation() {
        pendingGpsLocation = null
        views.forEach { view -> view.clearCurrentLocation() }
    }

    fun setShowAllLineLabels(arguments: Any?) {
        val enabled = (arguments as? Map<*, *>)?.get("enabled") as? Boolean ?: false
        pendingShowAllLineLabels = enabled
        views.forEach { view -> view.setShowAllLineLabels(enabled) }
    }

    fun setMarkerMoveMode(arguments: Any?) {
        val enabled = (arguments as? Map<*, *>)?.get("enabled") as? Boolean ?: false
        pendingMarkerMoveMode = enabled
        views.forEach { view -> view.setMarkerMoveMode(enabled) }
    }
}
