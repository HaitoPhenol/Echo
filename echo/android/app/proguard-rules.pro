# Echo release 混淆规则（G8）
# Flutter embedding（io.flutter.**）的 keep 规则由 Flutter Gradle 插件随 AAR 提供，
# 此处只需保底保留本应用自身类，避免 Manifest/入口组件被裁剪。
-keep class com.everse.echo.** { *; }
