package com.example.field_manager_app.v2

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import com.kakao.vectormap.KakaoMap
import com.kakao.vectormap.KakaoMapReadyCallback
import com.kakao.vectormap.LatLng
import com.kakao.vectormap.MapLifeCycleCallback
import com.kakao.vectormap.MapView
import com.kakao.vectormap.label.Label
import com.kakao.vectormap.label.LabelLayer
import com.kakao.vectormap.label.LabelOptions
import com.kakao.vectormap.label.LabelStyle
import com.kakao.vectormap.label.LabelStyles
import com.kakao.vectormap.label.LabelTextBuilder
import com.kakao.vectormap.label.LabelTextStyle
import io.flutter.plugin.platform.PlatformView

class NativeKakaoMapPlatformView(
    context: Context,
    private val viewId: Int
) : PlatformView {
    private val container = FrameLayout(context)
    private var mapView: MapView? = null
    private var kakaoMap: KakaoMap? = null
    private var labelLayer: LabelLayer? = null
    private var pendingMarkers: List<NativeMarkerDto>? = null
    private val renderedMarkers = linkedMapOf<String, NativeMarkerState>()
    private val styleCache = mutableMapOf<Int, LabelStyles>()

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
        finish()
        mapView = null
        kakaoMap = null
        labelLayer = null
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
        labelLayer?.removeAll()
        val removed = renderedMarkers.size
        renderedMarkers.clear()
        pendingMarkers = emptyList()
        if (removed > 0) {
            Log.d(NativeKakaoMapRegistry.LOG_TAG, "marker diff total=0 added=0 updated=0 removed=$removed reused=0")
        }
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
                    Log.d(NativeKakaoMapRegistry.LOG_TAG, "MapView $viewId ready.")
                    labelLayer = kakaoMap.labelManager?.layer
                    if (labelLayer == null) {
                        Log.w(NativeKakaoMapRegistry.LOG_TAG, "MapView $viewId ready without LabelLayer.")
                        return
                    }
                    pendingMarkers?.let { latest ->
                        pendingMarkers = null
                        applyMarkerDiff(latest)
                    }
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
                    renderedMarkers[marker.displayKey] = NativeMarkerState(marker.renderKey, label)
                    added++
                }
            } else if (current.renderKey != marker.renderKey) {
                current.label.remove()
                addMarkerLabel(layer, marker)?.let { label ->
                    renderedMarkers[marker.displayKey] = NativeMarkerState(marker.renderKey, label)
                    updated++
                }
            } else {
                reused++
            }
        }

        Log.d(
            NativeKakaoMapRegistry.LOG_TAG,
            "marker diff total=${markers.size} added=$added updated=$updated removed=$removed reused=$reused"
        )
    }

    private fun addMarkerLabel(layer: LabelLayer, marker: NativeMarkerDto): Label? {
        return runCatching {
            val title = marker.title.ifBlank { marker.groupName.ifBlank { marker.id } }
            layer.addLabel(
                LabelOptions
                    .from(marker.displayKey, LatLng.from(marker.lat, marker.lng))
                    .setStyles(styleForColor(marker.colorValue))
                    .setTexts(LabelTextBuilder().setTexts(title))
                    .setClickable(false)
                    .setTag(marker.displayKey)
            )
        }.onFailure {
            Log.w(NativeKakaoMapRegistry.LOG_TAG, "Label add failed displayKey=${marker.displayKey}", it)
        }.getOrNull()
    }

    private fun styleForColor(colorValue: Int): LabelStyles {
        return styleCache.getOrPut(colorValue) {
            LabelStyles.from(
                "field_marker_${java.lang.Long.toHexString(colorValue.toLong() and 0xffffffffL)}",
                LabelStyle
                    .from(createMarkerBitmap(colorValue))
                    .setTextStyles(LabelTextStyle.from(13, Color.rgb(35, 35, 35), 2, Color.WHITE))
                    .setTextGravity(Gravity.CENTER_HORIZONTAL)
            )
        }
    }

    private fun createMarkerBitmap(colorValue: Int): Bitmap {
        val size = 34
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (Color.alpha(colorValue) == 0) colorValue or Color.BLACK else colorValue
        }
        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 4f
            color = Color.WHITE
        }

        val center = size / 2f
        canvas.drawCircle(center, center, 12f, fill)
        canvas.drawCircle(center, center, 12f, border)
        return bitmap
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
    val label: Label
)

data class NativeMarkerDto(
    val displayKey: String,
    val renderKey: String,
    val id: String,
    val lat: Double,
    val lng: Double,
    val title: String,
    val groupName: String,
    val colorValue: Int
) {
    companion object {
        fun fromFlutterList(arguments: Any?): List<NativeMarkerDto> {
            val items = arguments as? List<*> ?: return emptyList()
            return items.mapNotNull { item ->
                val map = item as? Map<*, *> ?: return@mapNotNull null
                val lat = (map["lat"] as? Number)?.toDouble() ?: return@mapNotNull null
                val lng = (map["lng"] as? Number)?.toDouble() ?: return@mapNotNull null
                if (!lat.isFinite() || !lng.isFinite() || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
                    return@mapNotNull null
                }

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
                    colorValue = (map["colorValue"] as? Number)?.toLong()?.toInt() ?: Color.BLUE
                )
            }
        }
    }
}
