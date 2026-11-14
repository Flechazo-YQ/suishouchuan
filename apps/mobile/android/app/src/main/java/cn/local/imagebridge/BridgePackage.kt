package cn.local.imagebridge

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager

class BridgePackage : ReactPackage {
    override fun createNativeModules(context: ReactApplicationContext): List<NativeModule> = listOf(BridgeModule(context))
    override fun createViewManagers(context: ReactApplicationContext): List<ViewManager<*, *>> = listOf(CameraSurfaceManager(), VideoSurfaceManager())
}
