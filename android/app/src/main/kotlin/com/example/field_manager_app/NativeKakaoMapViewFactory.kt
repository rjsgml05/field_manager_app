package com.example.field_manager_app.v2

import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class NativeKakaoMapViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return NativeKakaoMapPlatformView(context, viewId)
    }

    companion object {
        const val VIEW_TYPE = "field_manager/native_kakao_map"
    }
}
