#!/usr/bin/env bash
# ============================================================================
#  错题本 APP · 一键组装脚本
#
#  作用：把当前目录下的「全文件」自动整理成 Flutter 需要的目录结构，
#        然后自动编译出 APK。
#
#  用法（把本文件和其它所有文件放在同一个文件夹里）：
#      bash setup.sh
#
#  脚本会自动完成：
#      1. 检查 Flutter 环境
#      2. 创建 lib/ android/ 等必要目录
#      3. 把 main.dart 放进 lib/
#      4. 生成全部 Android 配置文件
#      5. 拉取依赖并编译 APK
#      6. 把 APK 复制到当前目录，方便你取用
# ============================================================================
set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${BLUE}[信息]${NC} $1"; }
ok()    { echo -e "${GREEN}[成功]${NC} $1"; }
warn()  { echo -e "${YELLOW}[提示]${NC} $1"; }
fail()  { echo -e "${RED}[失败]${NC} $1"; exit 1; }

echo ""
echo "================================================"
echo "        错题本 APP · 自动组装与编译"
echo "================================================"
echo ""

# ---------- 1. 检查环境 ----------
info "检查 Flutter 环境..."
if ! command -v flutter >/dev/null 2>&1; then
  fail "未检测到 Flutter。请先安装：https://docs.flutter.dev/get-started/install"
fi
FLUTTER_VER=$(flutter --version 2>/dev/null | head -1)
ok "已检测到 $FLUTTER_VER"

# 检查 Android SDK
if ! flutter doctor 2>/dev/null | grep -q "Android toolchain.*✓"; then
  warn "Android toolchain 未就绪，编译可能失败。"
  warn "请先执行：flutter doctor --android-licenses  并全部同意"
  echo ""
  read -p "仍要继续吗？(y/N) " ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ] || exit 1
fi

# 检查关键文件
[ -f "main.dart" ] || fail "找不到 main.dart，请确认所有文件都在同一目录"
[ -f "pubspec.yaml" ] || fail "找不到 pubspec.yaml"
[ -f "AndroidManifest.xml" ] || fail "找不到 AndroidManifest.xml"
[ -f "mistake_template.docx" ] || fail "找不到 mistake_template.docx"
ok "源文件检查通过"

# ---------- 2. 创建目录结构 ----------
info "创建 Flutter 目录结构..."
mkdir -p lib
mkdir -p android/app/src/main/res/values
mkdir -p android/app/src/main/res/xml
mkdir -p android/app/src/main/kotlin/com/example/mistake_book
mkdir -p android/gradle/wrapper
mkdir -p .github/workflows
ok "目录创建完成"

# ---------- 3. 放置 Dart 源码 ----------
cp main.dart lib/main.dart
ok "lib/main.dart 就位"

# ---------- 4. 生成 Android 配置 ----------
info "生成 Android 配置文件..."

cat > android/app/src/main/AndroidManifest.xml << 'XMLEOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <application
        android:label="错题本"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:requestLegacyExternalStorage="true"
        android:usesCleartextTraffic="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data android:name="io.flutter.embedding.android.NormalTheme" android:resource="@style/NormalTheme" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data android:name="flutterEmbedding" android:value="2" />
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/file_paths" />
        </provider>
    </application>
    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:mimeType="application/vnd.openxmlformats-officedocument.wordprocessingml.document" />
        </intent>
        <intent>
            <action android:name="android.intent.action.SEND" />
            <data android:mimeType="*/*" />
        </intent>
    </queries>
</manifest>
XMLEOF

cat > android/app/src/main/res/xml/file_paths.xml << 'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <external-path name="external_files" path="." />
    <external-files-path name="ext_files" path="." />
    <files-path name="files" path="." />
    <cache-path name="cache" path="." />
</paths>
XMLEOF

cat > android/app/src/main/res/values/styles.xml << 'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@android:color/white</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
XMLEOF

cat > android/app/src/main/kotlin/com/example/mistake_book/MainActivity.kt << 'KTEOF'
package com.example.mistake_book

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
KTEOF

cat > android/app/build.gradle << 'GEOF'
plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

android {
    namespace = "com.example.mistake_book"
    compileSdk = 34
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.mistake_book"
        minSdk = 23
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.debug
            minifyEnabled = false
            shrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
GEOF

cat > android/settings.gradle << 'GEOF'
pluginManagement {
    def flutterSdkPath = {
        def properties = new Properties()
        file("local.properties").withInputStream { properties.load(it) }
        def flutterSdkPath = properties.getProperty("flutter.sdk")
        assert flutterSdkPath != null, "flutter.sdk not set in local.properties"
        return flutterSdkPath
    }()

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id "dev.flutter.flutter-plugin-loader" version "1.0.0"
    id "com.android.application" version "8.3.2" apply false
    id "org.jetbrains.kotlin.android" version "1.9.22" apply false
}

include ":app"
GEOF

cat > android/build.gradle << 'GEOF'
allprojects {
    repositories {
        // 国内镜像加速（先走镜像，失败再走官方）
        maven { url 'https://maven.aliyun.com/repository/google' }
        maven { url 'https://maven.aliyun.com/repository/central' }
        maven { url 'https://maven.aliyun.com/repository/public' }
        google()
        mavenCentral()
    }
}

rootProject.buildDir = "../build"
subprojects {
    project.buildDir = "${rootProject.buildDir}/${project.name}"
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register("clean", Delete) {
    delete rootProject.buildDir
}
GEOF

cat > android/gradle.properties << 'GEOF'
org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=2G -XX:+HeapDumpOnOutOfMemoryError
android.useAndroidX=true
android.enableJetifier=true
GEOF

cat > android/gradle/wrapper/gradle-wrapper.properties << 'GEOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.5-all.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
GEOF

ok "Android 配置生成完成"

# ---------- 5. 生成 GitHub Actions 配置 ----------
info "生成自动编译配置..."
cat > .github/workflows/build-apk.yml << 'YEOF'
name: 编译 APK
"on":
  push:
    branches: [ main, master ]
  workflow_dispatch:
jobs:
  build-apk:
    name: 构建 release APK
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'zulu'
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.22.0'
          channel: 'stable'
          cache: true
      - run: flutter pub get
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v4
        with:
          name: mistake-book-apk
          path: build/app/outputs/flutter-apk/app-release.apk
          retention-days: 90
YEOF
ok "自动编译配置生成完成"

# ---------- 6. 拉取依赖 ----------
echo ""
info "拉取项目依赖（首次较慢，请耐心等待）..."
if ! flutter pub get; then
  fail "依赖拉取失败。若网络慢，请重试或配置国内镜像"
fi
ok "依赖拉取完成"

# ---------- 7. 编译 APK ----------
echo ""
info "开始编译 APK（首次需 5-15 分钟）..."
echo ""
if flutter build apk --release; then
  APK="build/app/outputs/flutter-apk/app-release.apk"
  if [ -f "$APK" ]; then
    cp "$APK" ./错题本.apk
    echo ""
    echo "================================================"
    ok "编译成功！"
    echo "================================================"
    echo ""
    echo -e "  APK 文件位置：${GREEN}$(pwd)/错题本.apk${NC}"
    echo -e "  文件大小：$(du -h ./错题本.apk | cut -f1)"
    echo ""
    echo "  下一步：把这个 APK 传到手机，用卓易通安装即可。"
    echo ""
  else
    fail "编译完成但找不到 APK 文件"
  fi
else
  echo ""
  fail "编译失败。请把上方的报错信息发给开发者"
fi
