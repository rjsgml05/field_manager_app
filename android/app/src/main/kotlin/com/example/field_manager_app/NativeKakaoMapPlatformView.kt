package com.example.field_manager_app.v2

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import com.kakao.vectormap.KakaoMap
import com.kakao.vectormap.KakaoMapReadyCallback
import com.kakao.vectormap.LatLng
import com.kakao.vectormap.MapLifeCycleCallback
import com.kakao.vectormap.MapView
import com.kakao.vectormap.camera.CameraUpdateFactory
import com.kakao.vectormap.label.Label
import com.kakao.vectormap.label.LabelLayer
import com.kakao.vectormap.label.LabelOptions
import com.kakao.vectormap.label.LabelStyle
import com.kakao.vectormap.label.LabelLayerOptions
import com.kakao.vectormap.label.LabelStyles
import com.kakao.vectormap.label.CompetitionType
import com.kakao.vectormap.label.CompetitionUnit
import com.kakao.vectormap.route.RouteLine
import com.kakao.vectormap.route.RouteLineLayer
import com.kakao.vectormap.route.RouteLineOptions
import com.kakao.vectormap.route.RouteLineSegment
import com.kakao.vectormap.route.RouteLineStyle
import io.flutter.plugin.platform.PlatformView
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

class NativeKakaoMapPlatformView(
    context: Context,
    private val viewId: Int
) : PlatformView {
    private val container = object : FrameLayout(context) {
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (!markerMoveModeEnabled) {
            return super.dispatchTouchEvent(event)
        }

        val consumed = handleMarkerDragTouch(event)

        return if (consumed) {
            true
        } else {
            super.dispatchTouchEvent(event)
        }
    }
}

    private var mapView: MapView? = null
    private var kakaoMap: KakaoMap? = null
    private var labelLayer: LabelLayer? = null
    private var currentLocationLayer: LabelLayer? = null
    private var lineLabelLayer: LabelLayer? = null
    private var routeLineLayer: RouteLineLayer? = null
    private var pendingMarkers: List<NativeMarkerDto>? = null
    private var pendingLines: List<NativeLineDto>? = null
    private var pendingGpsLocation: NativeGpsLocation? = null
    private var pendingShowAllLineLabels = false
    private val renderedMarkers = linkedMapOf<String, NativeMarkerState>()
    private val renderedLines = linkedMapOf<String, NativeLineState>()
    private var nativeRouteSequence = 0L
    private val markerStyleCache = mutableMapOf<String, LabelStyles>()
    private val routeStyleCache = mutableMapOf<Int, RouteLineStyle>()
    private val lineLabelStyleCache = mutableMapOf<String, LabelStyles>()
    private val currentLocationStyle by lazy { createCurrentLocationStyle() }
    private var currentLocationLabel: Label? = null
    private var lastMarkerTapAtMs = 0L
    private var markerMoveModeEnabled = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingLongPressRunnable: Runnable? = null

    private var draggingMarkerKey: String? = null
    private var draggingMarkerOriginalPosition: LatLng? = null
    private var dragActivated = false
    private var dragLastPosition: LatLng? = null
    private var dragLastMoveAtMs = 0L

    private val longPressThresholdMs = 300L
    private val markerHitRadiusPx = 44f * context.resources.displayMetrics.density
    init {
        if (BuildConfig.KAKAO_NATIVE_APP_KEY.isBlank()) {
            showMissingKeyMessage(context)
            Log.w(
                NativeKakaoMapRegistry.LOG_TAG,
                "PlatformView $viewId created without KAKAO_NATIVE_APP_KEY; add it to android/local.properties."
            )
        } else {
            startMap(context)
        }
    }

    override fun getView(): View = container

    override fun dispose() {
        NativeKakaoMapRegistry.unregister(this)
        clearMarkers()
        clearLines()
        clearCurrentLocation()
        finish()
        mapView = null
        kakaoMap = null
        labelLayer = null
        currentLocationLayer = null
        lineLabelLayer = null
        routeLineLayer = null
        container.removeAllViews()
        Log.d(NativeKakaoMapRegistry.LOG_TAG, "PlatformView $viewId disposed.")
    }

    fun resume() {
        mapView?.resume()
    }

    fun pause() {
        mapView?.pause()
    }

    fun finish() {
        mapView?.let { view ->
            runCatching { view.pause() }
                .onFailure { Log.w(NativeKakaoMapRegistry.LOG_TAG, "MapView pause failed.", it) }
            runCatching { view.finish() }
                .onFailure { Log.w(NativeKakaoMapRegistry.LOG_TAG, "MapView finish failed.", it) }
        }
    }

    fun renderMarkers(markers: List<NativeMarkerDto>) {
        if (kakaoMap == null || labelLayer == null) {
            pendingMarkers = markers
            Log.d(NativeKakaoMapRegistry.LOG_TAG, "marker render pending total=${markers.size}")
            return
        }

        applyMarkerDiff(markers)
    }

    fun clearMarkers() {
        val removed = renderedMarkers.size
        renderedMarkers.values.forEach { it.label.remove() }
        renderedMarkers.clear()
        pendingMarkers = emptyList()
        if (removed > 0) {
            Log.d(NativeKakaoMapRegistry.LOG_TAG, "marker diff total=0 added=0 updated=0 removed=$removed reused=0")
        }
    }

    fun renderLines(lines: List<NativeLineDto>): Map<String, Int> {
        val visibleCount = lines.count { it.isVisible }
        if (kakaoMap == null || routeLineLayer == null) {
            pendingLines = lines
            Log.d(NativeKakaoMapRegistry.LOG_TAG, "line render pending total=${lines.size}")
            return mapOf(
                "incoming" to visibleCount,
                "rendered" to renderedLines.size,
                "added" to 0,
                "updated" to 0,
                "removed" to 0,
                "reused" to 0,
                "failed" to 0,
                "pending" to 1
            )
        }

        return applyLineDiff(lines)
    }

    fun clearLines() {
        val removed = renderedLines.size
        renderedLines.values.forEach { state ->
            state.routeLine.remove()
            state.titleLabel?.remove()
        }
        renderedLines.clear()
        pendingLines = emptyList()
        if (removed > 0) {
            Log.d(NativeKakaoMapRegistry.LOG_TAG, "line diff total=0 added=0 updated=0 removed=$removed reused=0")
        }
    }

    fun setShowAllLineLabels(enabled: Boolean) {
        pendingShowAllLineLabels = enabled
        for ((_, state) in renderedLines) {
            if (enabled) {
                ensureLineTitleLabel(state.line)
            } else {
                state.titleLabel?.remove()
                state.titleLabel = null
            }
        }
    }

    fun setMarkerMoveMode(enabled: Boolean) {
        if (!enabled) resetMarkerDrag(restore = true)
        markerMoveModeEnabled = enabled
        Log.d(NativeKakaoMapRegistry.LOG_TAG, "marker move mode enabled=$enabled")
    }

    fun moveTo(lat: Double, lng: Double, level: Int) {
        val map = kakaoMap ?: return
        if (!isValidCoordinate(lat, lng)) return

        runCatching {
            map.moveCamera(CameraUpdateFactory.newCenterPosition(LatLng.from(lat, lng), level))
        }.onFailure {
            Log.w(NativeKakaoMapRegistry.LOG_TAG, "moveTo failed.", it)
        }
    }

    fun showCurrentLocation(location: NativeGpsLocation) {
        if (kakaoMap == null || labelLayer == null) {
            pendingGpsLocation = location
            return
        }

        val layer = currentLocationLayer ?: labelLayer ?: return
        if (currentLocationLayer == null) {
            Log.w(
                NativeKakaoMapRegistry.LOG_TAG,
                "current location custom layer unavailable; fallback to marker layer"
            )
        }
        val position = LatLng.from(location.lat, location.lng)
        currentLocationLabel?.remove()
        currentLocationLabel = layer.addLabel(
            LabelOptions
                .from("field_current_location", position)
                .setStyles(currentLocationStyle)
                .setClickable(false)
        )
        pendingGpsLocation = location
        if (location.moveCamera) {
            moveTo(location.lat, location.lng, location.level ?: 15)
        }
    }

    fun clearCurrentLocation() {
        currentLocationLabel?.remove()
        currentLocationLabel = null
        pendingGpsLocation = null
    }
private fun scheduleMarkerLongPress() {
    cancelPendingLongPress()

    val runnable = Runnable {
        val key = draggingMarkerKey

        if (
            markerMoveModeEnabled &&
            key != null &&
            !dragActivated
        ) {
            dragActivated = true

            Log.d(
                NativeKakaoMapRegistry.LOG_TAG,
                "marker drag activated key=${key.hashCode()}"
            )
        }
    }

    pendingLongPressRunnable = runnable
    mainHandler.postDelayed(runnable, longPressThresholdMs)
}

private fun cancelPendingLongPress() {
    pendingLongPressRunnable?.let { runnable ->
        mainHandler.removeCallbacks(runnable)
    }

    pendingLongPressRunnable = null
}
private fun handleMarkerDragTouch(event: MotionEvent): Boolean {
    if (!markerMoveModeEnabled) return false

    val map = kakaoMap ?: return false

    return when (event.actionMasked) {
        MotionEvent.ACTION_DOWN -> {
            val hit = findNearestMarker(
                x = event.x,
                y = event.y,
                map = map
            ) ?: return false

            draggingMarkerKey = hit.first
            draggingMarkerOriginalPosition = hit.second.label.getPosition()
            dragActivated = false
            dragLastPosition = hit.second.label.getPosition()
            dragLastMoveAtMs = 0L

            scheduleMarkerLongPress()

            Log.d(
                NativeKakaoMapRegistry.LOG_TAG,
                "marker drag candidate key=${hit.first.hashCode()}"
            )

            true
        }

        MotionEvent.ACTION_MOVE -> {
            val key = draggingMarkerKey ?: return false
            val state = renderedMarkers[key]
                ?: return resetMarkerDrag(restore = false).let { false }

            if (!dragActivated) {
                return true
            }

            val now = SystemClock.elapsedRealtime()

            if (now - dragLastMoveAtMs < 16L) {
                return true
            }

            dragLastMoveAtMs = now

            val position = map.fromScreenPoint(
                event.x.toInt(),
                event.y.toInt()
            )

            dragLastPosition = position
            state.label.moveTo(position, 0)

            true
        }

        MotionEvent.ACTION_UP -> {
            cancelPendingLongPress()

            val key = draggingMarkerKey
            val state = key?.let { renderedMarkers[it] }
            val position = dragLastPosition

            val shouldSave =
                dragActivated &&
                state != null &&
                position != null

            if (shouldSave) {
                Log.d(
                    NativeKakaoMapRegistry.LOG_TAG,
                    "marker drag end key=${key.hashCode()}"
                )

                NativeKakaoMapRegistry.sendMarkerDragEnd(
                    state!!.marker,
                    position!!.latitude,
                    position.longitude
                )

                resetMarkerDrag(restore = false)
            } else {
                resetMarkerDrag(restore = true)
            }

            key != null
        }

        MotionEvent.ACTION_CANCEL -> {
            val hadDrag = draggingMarkerKey != null

            resetMarkerDrag(restore = true)

            hadDrag
        }

        else -> draggingMarkerKey != null
    }
}
    private fun findNearestMarker(x: Float, y: Float, map: KakaoMap): Pair<String, NativeMarkerState>? {
        var bestKey: String? = null
        var bestState: NativeMarkerState? = null
        var bestDistance = Float.MAX_VALUE
        val radius = markerHitRadiusPx

        for ((key, state) in renderedMarkers) {
            val point = map.toScreenPoint(state.label.getPosition()) ?: continue
            val dx = point.x.toFloat() - x
            val dy = point.y.toFloat() - y
            val distance = sqrt((dx * dx) + (dy * dy))
            if (distance <= radius && distance < bestDistance) {
                bestKey = key
                bestState = state
                bestDistance = distance
            }
        }

        val key = bestKey ?: return null
        val state = bestState ?: return null
        return key to state
    }

    private fun resetMarkerDrag(restore: Boolean) {
    cancelPendingLongPress()

    val key = draggingMarkerKey

    if (restore && key != null) {
        val original = draggingMarkerOriginalPosition
        val state = renderedMarkers[key]

        if (original != null && state != null) {
            state.label.moveTo(original, 0)
        }
    }

    draggingMarkerKey = null
    draggingMarkerOriginalPosition = null
    dragActivated = false
    dragLastPosition = null
    dragLastMoveAtMs = 0L
}

    private fun startMap(context: Context) {
        val view = MapView(context)
        mapView = view
        container.addView(
            view,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        NativeKakaoMapRegistry.register(this)
        Log.d(NativeKakaoMapRegistry.LOG_TAG, "Starting native Kakao MapView $viewId.")

        view.start(
            object : MapLifeCycleCallback() {
                override fun onMapDestroy() {
                    Log.d(NativeKakaoMapRegistry.LOG_TAG, "MapView $viewId destroyed.")
                }

                override fun onMapError(error: Exception) {
                    Log.e(NativeKakaoMapRegistry.LOG_TAG, "MapView $viewId error: ${error.message}", error)
                }
            },
            object : KakaoMapReadyCallback() {
                override fun onMapReady(kakaoMap: KakaoMap) {
                    this@NativeKakaoMapPlatformView.kakaoMap = kakaoMap
                    val labelManager = kakaoMap.labelManager
                    val defaultLabelLayer = labelManager?.layer
                    labelLayer = labelManager?.addLayer(
                        LabelLayerOptions
                            .from("field_marker_layer")
                            .setZOrder(6000)
                            .setCompetitionType(CompetitionType.None)
                            .setCompetitionUnit(CompetitionUnit.IconAndText)
                            .setClickable(true)
                    ) ?: defaultLabelLayer
                    if (defaultLabelLayer != null && labelLayer == defaultLabelLayer) {
                        Log.w(
                            NativeKakaoMapRegistry.LOG_TAG,
                            "marker custom layer unavailable; fallback to default label layer"
                        )
                    } else if (labelLayer != null) {
                        Log.d(
                            NativeKakaoMapRegistry.LOG_TAG,
                            "marker layer created id=field_marker_layer zOrder=6000 competition=None"
                        )
                    }
                    currentLocationLayer = labelManager?.addLayer(
                        LabelLayerOptions
                            .from("field_current_location_layer")
                            .setZOrder(15000)
                            .setCompetitionType(CompetitionType.None)
                            .setCompetitionUnit(CompetitionUnit.IconAndText)
                            .setClickable(false)
                    )
                    if (currentLocationLayer != null) {
                        Log.d(
                            NativeKakaoMapRegistry.LOG_TAG,
                            "current location layer created id=field_current_location_layer zOrder=15000 competition=None"
                        )
                    }
                    lineLabelStyleCache.clear()
                    lineLabelLayer = labelManager?.addLayer(
                        LabelLayerOptions
                            .from("field_line_label_layer")
                            .setZOrder(20000)
                            .setCompetitionType(CompetitionType.None)
                            .setCompetitionUnit(CompetitionUnit.IconAndText)
                            .setClickable(false)
                    )
                    if (lineLabelLayer != null) {
                        Log.d(
                            NativeKakaoMapRegistry.LOG_TAG,
                            "line label layer created id=field_line_label_layer zOrder=20000 competition=None"
                        )
                    }
                    routeLineLayer = kakaoMap.routeLineManager?.layer
                    kakaoMap.setOnLabelClickListener { _, _, label ->
     val marker = label.tag as? NativeMarkerDto
        ?: return@setOnLabelClickListener false

    lastMarkerTapAtMs = SystemClock.elapsedRealtime()

    if (markerMoveModeEnabled) {
        return@setOnLabelClickListener true
    }

    NativeKakaoMapRegistry.sendMarkerTap(marker)

    true
}
                    kakaoMap.setOnMapClickListener { _, position, _, _ ->
                        val now = SystemClock.elapsedRealtime()
                        if (now - lastMarkerTapAtMs > 250L) {
                            NativeKakaoMapRegistry.sendMapTap(position.latitude, position.longitude)
                        }
                    }

                    Log.d(NativeKakaoMapRegistry.LOG_TAG, "MapView $viewId ready.")
                    if (labelLayer == null) {
                        Log.w(NativeKakaoMapRegistry.LOG_TAG, "MapView $viewId ready without LabelLayer.")
                        return
                    }
                    if (routeLineLayer == null) {
                        Log.w(NativeKakaoMapRegistry.LOG_TAG, "MapView $viewId ready without RouteLineLayer.")
                    }

                    pendingMarkers?.let { latest ->
                        pendingMarkers = null
                        applyMarkerDiff(latest)
                    }
                    pendingLines?.let { latest ->
                        pendingLines = null
                        applyLineDiff(latest)
                    }
                    setShowAllLineLabels(pendingShowAllLineLabels)
                    pendingGpsLocation?.let { showCurrentLocation(it) }
                    NativeKakaoMapRegistry.sendMapReady()
                }

                override fun getPosition(): LatLng = LatLng.from(35.1795, 129.0756)

                override fun getZoomLevel(): Int = 15

                override fun getViewName(): String = "FieldManagerNativeMap-$viewId"
            }
        )
        runCatching { view.resume() }
            .onFailure { Log.w(NativeKakaoMapRegistry.LOG_TAG, "Initial MapView resume failed.", it) }
    }

    private fun applyMarkerDiff(markers: List<NativeMarkerDto>) {
        val layer = labelLayer ?: return
        val nextByKey = markers.associateBy { it.displayKey }
        var added = 0
        var updated = 0
        var removed = 0
        var reused = 0

        val staleKeys = renderedMarkers.keys - nextByKey.keys
        for (key in staleKeys) {
            renderedMarkers.remove(key)?.label?.remove()
            removed++
        }

        for (marker in markers) {
            val current = renderedMarkers[marker.displayKey]
            if (current == null) {
                addMarkerLabel(layer, marker)?.let { label ->
                    renderedMarkers[marker.displayKey] = NativeMarkerState(marker.renderKey, label, marker)
                    added++
                }
            } else if (current.renderKey != marker.renderKey) {
                current.label.remove()
                addMarkerLabel(layer, marker)?.let { label ->
                    renderedMarkers[marker.displayKey] = NativeMarkerState(marker.renderKey, label, marker)
                    updated++
                }
            } else {
                current.marker = marker
                reused++
            }
        }

        Log.d(
            NativeKakaoMapRegistry.LOG_TAG,
            "marker diff total=${markers.size} added=$added updated=$updated removed=$removed reused=$reused"
        )
    }

    private fun applyLineDiff(lines: List<NativeLineDto>): Map<String, Int> {
        val layer = routeLineLayer ?: return mapOf(
            "incoming" to 0,
            "rendered" to renderedLines.size,
            "added" to 0,
            "updated" to 0,
            "removed" to 0,
            "reused" to 0,
            "failed" to lines.count { it.isVisible },
            "pending" to 0
        )
        val visibleLines = lines.filter { it.isVisible }
        val nextByKey = visibleLines.associateBy { it.displayKey }
        var added = 0
        var updated = 0
        var removed = 0
        var reused = 0
        var failed = 0

        val staleKeys = renderedLines.keys - nextByKey.keys
        for (key in staleKeys) {
            renderedLines.remove(key)?.let { state ->
                state.routeLine.remove()
                state.titleLabel?.remove()
            }
            removed++
        }

        for (line in visibleLines) {
            val current = renderedLines[line.displayKey]
            if (current == null) {
                val addedRoute = addRouteLine(layer, line)
                if (addedRoute != null) {
                    val (nativeRouteId, routeLine) = addedRoute
                    val state = NativeLineState(line.renderKey, nativeRouteId, routeLine, line, null)
                    renderedLines[line.displayKey] = state
                    if (pendingShowAllLineLabels) ensureLineTitleLabel(line)
                    added++
                } else {
                    failed++
                }
            } else if (current.renderKey != line.renderKey) {
                val addedRoute = addRouteLine(layer, line)
                if (addedRoute != null) {
                    val (nativeRouteId, routeLine) = addedRoute
                    current.routeLine.remove()
                    current.titleLabel?.remove()
                    val state = NativeLineState(line.renderKey, nativeRouteId, routeLine, line, null)
                    renderedLines[line.displayKey] = state
                    if (pendingShowAllLineLabels) ensureLineTitleLabel(line)
                    updated++
                } else {
                    reused++
                    Log.w(
                        NativeKakaoMapRegistry.LOG_TAG,
                        "line update failed; keep old route displayKey=${line.displayKey} oldRouteId=${current.nativeRouteId} oldRenderKey=${current.renderKey} newRenderKey=${line.renderKey}"
                    )
                    failed++
                }
            } else {
                current.line = line
                reused++
            }
        }

        Log.d(
            NativeKakaoMapRegistry.LOG_TAG,
            "line diff total=${visibleLines.size} rendered=${renderedLines.size} added=$added updated=$updated removed=$removed reused=$reused failed=$failed"
        )
        return mapOf(
            "incoming" to visibleLines.size,
            "rendered" to renderedLines.size,
            "added" to added,
            "updated" to updated,
            "removed" to removed,
            "reused" to reused,
            "failed" to failed,
            "pending" to 0
        )
    }

    private fun addMarkerLabel(layer: LabelLayer, marker: NativeMarkerDto): Label? {
        return runCatching {
            layer.addLabel(
                LabelOptions
                    .from(marker.displayKey, LatLng.from(marker.lat, marker.lng))
                    .setStyles(styleForMarker(marker))
                    .setClickable(true)
                    .setTag(marker)
            )
        }.onFailure {
            Log.w(NativeKakaoMapRegistry.LOG_TAG, "Label add failed displayKey=${marker.displayKey}", it)
        }.getOrNull()
    }

    private fun buildNativeRouteId(line: NativeLineDto): String {
        nativeRouteSequence += 1
        val raw = "${line.displayKey}|${line.renderKey}|$nativeRouteSequence|${System.nanoTime()}"
        return "route_${Integer.toUnsignedString(raw.hashCode(), 16)}"
    }

    private fun addRouteLine(layer: RouteLineLayer, line: NativeLineDto): Pair<String, RouteLine>? {
        val points = line.points
            .filter { isValidCoordinate(it.lat, it.lng) }
            .map { LatLng.from(it.lat, it.lng) }
        if (points.size < 2) {
            Log.w(
                NativeKakaoMapRegistry.LOG_TAG,
                "RouteLine add skipped invalid points displayKey=${line.displayKey} points=${points.size}"
            )
            return null
        }

        val nativeRouteId = buildNativeRouteId(line)
        return runCatching {
            val segment = RouteLineSegment.from(points, styleForLine(line.colorValue))
            val routeLine = layer.addRouteLine(
                RouteLineOptions
                    .from(nativeRouteId, segment)
                    .setVisible(true)
                    .setTag(line.displayKey)
            )
            nativeRouteId to routeLine
        }.onFailure {
            Log.w(
                NativeKakaoMapRegistry.LOG_TAG,
                "RouteLine add failed displayKey=${line.displayKey} nativeRouteId=$nativeRouteId",
                it
            )
        }.getOrNull()
    }

    private fun ensureLineTitleLabel(line: NativeLineDto) {
        if (!pendingShowAllLineLabels || line.title.isBlank()) return
        val layer = lineLabelLayer ?: return
        val state = renderedLines[line.displayKey] ?: return
        state.titleLabel?.remove()
        val midpoint = line.midpoint() ?: return
        state.titleLabel = layer.addLabel(
            LabelOptions
                .from("field_line_label_${line.displayKey.hashCode()}", LatLng.from(midpoint.lat, midpoint.lng))
                .setStyles(styleForLineLabel(line.colorValue, line.title))
                .setClickable(false)
        )
        Log.d(
            NativeKakaoMapRegistry.LOG_TAG,
            "line label added layer=field_line_label_layer titleHash=${line.title.hashCode()}"
        )
    }

    private fun styleForMarker(marker: NativeMarkerDto): LabelStyles {
        val title = marker.title.ifBlank { marker.groupName.ifBlank { marker.id } }
        val key = "${marker.colorValue}|${marker.isChecked}|$title"
        return markerStyleCache.getOrPut(key) {
            val bitmap = createMarkerBitmap(marker.colorValue, marker.isChecked, title)
            LabelStyles.from(
                "field_marker_${key.hashCode()}",
                LabelStyle
                    .from(bitmap)
                    .setAnchorPoint(0.5f, 13f / bitmap.height.toFloat())
            )
        }
    }

    private fun styleForLine(colorValue: Int): RouteLineStyle {
        return routeStyleCache.getOrPut(colorValue) {
            RouteLineStyle.from(7f, normalizedColor(colorValue), 2f, Color.WHITE)
        }
    }

    private fun styleForLineLabel(colorValue: Int, title: String): LabelStyles {
        val key = "${LINE_LABEL_STYLE_VERSION}|${colorValue}|$title"
        return lineLabelStyleCache.getOrPut(key) {
            Log.d(
                NativeKakaoMapRegistry.LOG_TAG,
                "line label style border=6.0 version=$LINE_LABEL_STYLE_VERSION"
            )
            LabelStyles.from(
                "field_line_label_${key.hashCode()}",
                LabelStyle
                    .from(createLineLabelBitmap(title, colorValue))
                    .setAnchorPoint(0.5f, 0.5f)
            )
        }
    }

    private fun createCurrentLocationStyle(): LabelStyles {
        val size = 58
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val center = size / 2f
        val halo = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(72, 30, 125, 255)
            style = Paint.Style.FILL
        }
        val outerRing = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(12, 38, 82)
            style = Paint.Style.STROKE
            strokeWidth = 4f
        }
        val whiteRing = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = 5f
        }
        val core = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(30, 125, 255)
            style = Paint.Style.FILL
        }
        val centerDot = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.FILL
        }
        canvas.drawCircle(center, center, 27f, halo)
        canvas.drawCircle(center, center, 18f, outerRing)
        canvas.drawCircle(center, center, 14f, whiteRing)
        canvas.drawCircle(center, center, 11f, core)
        canvas.drawCircle(center, center, 3.5f, centerDot)
        return LabelStyles.from(
            "field_current_location_v2",
            LabelStyle.from(bitmap).setAnchorPoint(0.5f, 0.5f)
        )
    }

    private fun createMarkerBitmap(colorValue: Int, isChecked: Boolean, title: String): Bitmap {
        val text = title.trim().ifBlank { " " }.take(12)
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(35, 35, 35)
            textSize = 15f
            textAlign = Paint.Align.CENTER
            typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD)
        }
        val textWidth = textPaint.measureText(text)
        val labelHorizontalPadding = 3.5f
        val labelVerticalPadding = 2.5f
        val labelWidth = max(14f, textWidth + (labelHorizontalPadding * 2f))
        val width = max(34, min(140, labelWidth.toInt() + 4))
        val fontMetrics = textPaint.fontMetrics
        val labelHeight = (fontMetrics.descent - fontMetrics.ascent) + (labelVerticalPadding * 2f)
        val height = 51
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = normalizedColor(colorValue) }
        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 4f
            color = Color.WHITE
        }
        val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(55, 0, 0, 0) }

        val cx = width / 2f
        val cy = 13f
        canvas.drawCircle(cx + 1.5f, cy + 2f, 13f, shadow)
        canvas.drawCircle(cx, cy, 12f, fill)
        canvas.drawCircle(cx, cy, 12f, border)

        if (isChecked) {
            val badgeRadius = 5.5f
            val badgeCx = min(cx + 9f, width - badgeRadius - 1f)
            val badgeCy = max(cy - 7f, badgeRadius + 1f)
            val badgeFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                style = Paint.Style.FILL
            }
            val badgeBorder = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.rgb(45, 45, 45)
                style = Paint.Style.STROKE
                strokeWidth = 1.8f
            }
            val badgeCheck = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.rgb(35, 35, 35)
                style = Paint.Style.STROKE
                strokeWidth = 1.8f
                strokeCap = Paint.Cap.ROUND
                strokeJoin = Paint.Join.ROUND
            }
            canvas.drawCircle(badgeCx, badgeCy, badgeRadius, badgeFill)
            canvas.drawCircle(badgeCx, badgeCy, badgeRadius, badgeBorder)
            canvas.drawLine(
                badgeCx - 2.8f,
                badgeCy,
                badgeCx - 0.8f,
                badgeCy + 2.2f,
                badgeCheck
            )
            canvas.drawLine(
                badgeCx - 0.8f,
                badgeCy + 2.2f,
                badgeCx + 3.2f,
                badgeCy - 2.6f,
                badgeCheck
            )
        }

        val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(225, 255, 255, 255) }
        val labelLeft = cx - (labelWidth / 2f)
        val labelTop = 30f
        val labelRight = cx + (labelWidth / 2f)
        val labelBottom = labelTop + labelHeight
        canvas.drawRoundRect(labelLeft, labelTop, labelRight, labelBottom, 6f, 6f, bg)
        val textBaseline = labelTop + labelVerticalPadding - fontMetrics.ascent
        canvas.drawText(text, cx, textBaseline, textPaint)
        return bitmap
    }

    private fun createLineLabelBitmap(title: String, colorValue: Int): Bitmap {
        val text = title.trim().ifBlank { " " }.take(16)
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textSize = 24f
            textAlign = Paint.Align.CENTER
            typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD)
        }
        val horizontalPadding = 12f
        val verticalPadding = 7f
        val borderWidth = 6f
        val shadowMargin = 4f
        val fontMetrics = textPaint.fontMetrics
        val width = max(
            70,
            min(
                240,
                (textPaint.measureText(text) + (horizontalPadding * 2f) + (borderWidth * 2f) + shadowMargin).toInt() + 1
            )
        )
        val height = max(
            44,
            ((fontMetrics.descent - fontMetrics.ascent) + (verticalPadding * 2f) + (borderWidth * 2f) + shadowMargin).toInt() + 1
        )
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(55, 0, 0, 0) }
        val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = normalizedColor(colorValue)
            style = Paint.Style.STROKE
            strokeWidth = borderWidth
        }
        val rectInset = (borderWidth / 2f) + 1f
        canvas.drawRoundRect(
            rectInset + 1f,
            rectInset + 2f,
            width - rectInset + 1f,
            height - rectInset + 2f,
            12f,
            12f,
            shadow
        )
        canvas.drawRoundRect(rectInset, rectInset, width - rectInset, height - rectInset, 12f, 12f, bg)
        canvas.drawRoundRect(rectInset, rectInset, width - rectInset, height - rectInset, 12f, 12f, stroke)
        val baseline = (height / 2f) - ((fontMetrics.ascent + fontMetrics.descent) / 2f)
        val textShadow = Paint(textPaint).apply { color = Color.argb(55, 255, 255, 255) }
        canvas.drawText(text, (width / 2f) + 1f, baseline + 1f, textShadow)
        canvas.drawText(text, width / 2f, baseline, textPaint)
        return bitmap
    }

    private fun normalizedColor(colorValue: Int): Int {
        return if (Color.alpha(colorValue) == 0) colorValue or Color.BLACK else colorValue
    }

    private fun showMissingKeyMessage(context: Context) {
        container.setBackgroundColor(Color.rgb(245, 245, 245))
        container.addView(
            TextView(context).apply {
                text = "KAKAO_NATIVE_APP_KEY is missing in android/local.properties"
                setTextColor(Color.rgb(40, 40, 40))
                textAlignment = View.TEXT_ALIGNMENT_CENTER
                gravity = Gravity.CENTER
            },
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
    }
}

data class NativeMarkerState(
    val renderKey: String,
    val label: Label,
    var marker: NativeMarkerDto
)

data class NativeLineState(
    val renderKey: String,
    val nativeRouteId: String,
    val routeLine: RouteLine,
    var line: NativeLineDto,
    var titleLabel: Label?
)

data class NativePoint(
    val lat: Double,
    val lng: Double
)

data class NativeMarkerDto(
    val displayKey: String,
    val renderKey: String,
    val id: String,
    val lat: Double,
    val lng: Double,
    val title: String,
    val groupName: String,
    val colorValue: Int,
    val isChecked: Boolean,
    val canonicalMarkerId: String?,
    val originalMarkerId: String?,
    val sourceMarkerId: String?,
    val parentMarkerId: String?
) {
    fun toEventMap(): Map<String, Any?> = mapOf(
        "event" to "markerTap",
        "displayKey" to displayKey,
        "id" to id,
        "canonicalMarkerId" to canonicalMarkerId,
        "originalMarkerId" to originalMarkerId,
        "sourceMarkerId" to sourceMarkerId,
        "parentMarkerId" to parentMarkerId
    )

    fun toDragEndEventMap(lat: Double, lng: Double): Map<String, Any?> = mapOf(
        "event" to "markerDragEnd",
        "displayKey" to displayKey,
        "id" to id,
        "lat" to lat,
        "lng" to lng,
        "canonicalMarkerId" to canonicalMarkerId,
        "originalMarkerId" to originalMarkerId,
        "sourceMarkerId" to sourceMarkerId,
        "parentMarkerId" to parentMarkerId
    )

    companion object {
        fun fromFlutterList(arguments: Any?): List<NativeMarkerDto> {
            val items = arguments as? List<*> ?: return emptyList()
            return items.mapNotNull { item ->
                val map = item as? Map<*, *> ?: return@mapNotNull null
                val lat = (map["lat"] as? Number)?.toDouble() ?: return@mapNotNull null
                val lng = (map["lng"] as? Number)?.toDouble() ?: return@mapNotNull null
                if (!isValidCoordinate(lat, lng)) return@mapNotNull null

                val displayKey = map["displayKey"]?.toString()?.trim().orEmpty()
                if (displayKey.isEmpty()) return@mapNotNull null

                NativeMarkerDto(
                    displayKey = displayKey,
                    renderKey = map["renderKey"]?.toString().orEmpty(),
                    id = map["id"]?.toString().orEmpty(),
                    lat = lat,
                    lng = lng,
                    title = map["title"]?.toString().orEmpty(),
                    groupName = map["groupName"]?.toString().orEmpty(),
                    colorValue = (map["colorValue"] as? Number)?.toLong()?.toInt() ?: Color.BLUE,
                    isChecked = map["isChecked"] == true,
                    canonicalMarkerId = map["canonicalMarkerId"]?.toString(),
                    originalMarkerId = map["originalMarkerId"]?.toString(),
                    sourceMarkerId = map["sourceMarkerId"]?.toString(),
                    parentMarkerId = map["parentMarkerId"]?.toString()
                )
            }
        }
    }
}

data class NativeLineDto(
    val displayKey: String,
    val renderKey: String,
    val id: String,
    val title: String,
    val description: String,
    val points: List<NativePoint>,
    val markerIds: List<String>,
    val colorValue: Int,
    val isVisible: Boolean,
    val canonicalLineId: String?,
    val originalLineId: String?,
    val sourceLineId: String?
) {
    fun midpoint(): NativePoint? {
        if (points.isEmpty()) return null
        return points[points.size / 2]
    }

    companion object {
        fun fromFlutterList(arguments: Any?): List<NativeLineDto> {
            val items = arguments as? List<*> ?: return emptyList()
            return items.mapNotNull { item ->
                val map = item as? Map<*, *> ?: return@mapNotNull null
                val displayKey = map["displayKey"]?.toString()?.trim().orEmpty()
                if (displayKey.isEmpty()) return@mapNotNull null

                val points = (map["points"] as? List<*>)?.mapNotNull { point ->
                    val p = point as? Map<*, *> ?: return@mapNotNull null
                    val lat = (p["lat"] as? Number)?.toDouble() ?: return@mapNotNull null
                    val lng = (p["lng"] as? Number)?.toDouble() ?: return@mapNotNull null
                    if (!isValidCoordinate(lat, lng)) return@mapNotNull null
                    NativePoint(lat, lng)
                } ?: emptyList()
                if (points.size < 2) return@mapNotNull null

                NativeLineDto(
                    displayKey = displayKey,
                    renderKey = map["renderKey"]?.toString().orEmpty(),
                    id = map["id"]?.toString().orEmpty(),
                    title = map["title"]?.toString().orEmpty(),
                    description = map["description"]?.toString().orEmpty(),
                    points = points,
                    markerIds = (map["markerIds"] as? List<*>)?.map { it.toString() } ?: emptyList(),
                    colorValue = (map["colorValue"] as? Number)?.toLong()?.toInt() ?: Color.BLUE,
                    isVisible = map["isVisible"] != false,
                    canonicalLineId = map["canonicalLineId"]?.toString(),
                    originalLineId = map["originalLineId"]?.toString(),
                    sourceLineId = map["sourceLineId"]?.toString()
                )
            }
        }
    }
}

data class NativeGpsLocation(
    val lat: Double,
    val lng: Double,
    val title: String,
    val moveCamera: Boolean,
    val level: Int?
) {
    companion object {
        fun fromFlutterMap(arguments: Any?, defaultMoveCamera: Boolean): NativeGpsLocation? {
            val map = arguments as? Map<*, *> ?: return null
            val lat = (map["lat"] as? Number)?.toDouble() ?: return null
            val lng = (map["lng"] as? Number)?.toDouble() ?: return null
            if (!isValidCoordinate(lat, lng)) return null
            return NativeGpsLocation(
                lat = lat,
                lng = lng,
                title = map["title"]?.toString().orEmpty(),
                moveCamera = (map["moveCamera"] as? Boolean) ?: defaultMoveCamera,
                level = ((map["zoomLevel"] ?: map["level"]) as? Number)?.toInt()
            )
        }
    }
}

private const val LINE_LABEL_STYLE_VERSION = 2

private fun isValidCoordinate(lat: Double, lng: Double): Boolean {
    return lat.isFinite() && lng.isFinite() && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
}

