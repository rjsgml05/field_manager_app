package com.example.field_manager_app.v2

import android.content.Context
import android.graphics.Color
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import com.kakao.vectormap.KakaoMap
import com.kakao.vectormap.KakaoMapReadyCallback
import com.kakao.vectormap.LatLng
import com.kakao.vectormap.MapLifeCycleCallback
import com.kakao.vectormap.MapView
import io.flutter.plugin.platform.PlatformView

class NativeKakaoMapPlatformView(
    context: Context,
    private val viewId: Int
) : PlatformView {
    private val container = FrameLayout(context)
    private var mapView: MapView? = null

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
        mapView?.let { view ->
            NativeKakaoMapRegistry.unregister(view)
            runCatching { view.pause() }
                .onFailure { Log.w(NativeKakaoMapRegistry.LOG_TAG, "MapView pause on dispose failed.", it) }
            runCatching { view.finish() }
                .onFailure { Log.w(NativeKakaoMapRegistry.LOG_TAG, "MapView finish on dispose failed.", it) }
        }
        mapView = null
        container.removeAllViews()
        Log.d(NativeKakaoMapRegistry.LOG_TAG, "PlatformView $viewId disposed.")
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

        NativeKakaoMapRegistry.register(view)
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
                    Log.d(NativeKakaoMapRegistry.LOG_TAG, "MapView $viewId ready.")
                }

                override fun getPosition(): LatLng = LatLng.from(35.1795, 129.0756)

                override fun getZoomLevel(): Int = 15

                override fun getViewName(): String = "FieldManagerNativeMap-$viewId"
            }
        )
        runCatching { view.resume() }
            .onFailure { Log.w(NativeKakaoMapRegistry.LOG_TAG, "Initial MapView resume failed.", it) }
    }

    private fun showMissingKeyMessage(context: Context) {
        container.setBackgroundColor(Color.rgb(245, 245, 245))
        container.addView(
            TextView(context).apply {
                text = "KAKAO_NATIVE_APP_KEY is missing in android/local.properties"
                setTextColor(Color.rgb(40, 40, 40))
                textAlignment = View.TEXT_ALIGNMENT_CENTER
                gravity = android.view.Gravity.CENTER
            },
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
    }
}
