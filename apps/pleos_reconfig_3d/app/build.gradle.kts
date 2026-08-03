plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.keti.pleos.reconfig3d"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.keti.pleos.reconfig3d"
        // Filament needs 21+, and the split BLUETOOTH_SCAN/CONNECT model is the only
        // one this app implements, so there is nothing to gain from going lower.
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    // The glb is already a compressed-ish JSON payload with an embedded base64
    // buffer; letting aapt deflate it again only costs inflate time at load.
    androidResources {
        noCompress += "glb"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.core:core-ktx:1.15.0")

    // Filament: the renderer, the glTF loader, and the helper that owns the
    // engine/scene/camera plumbing so this app does not reimplement it.
    // Pinned to the version whose API this app was written against: FilamentInstance
    // owns the material instances, and Material.hasParameter is what keeps a
    // setParameter on a shader without that parameter from aborting in native code.
    val filament = "1.74.0"
    implementation("com.google.android.filament:filament-android:$filament")
    implementation("com.google.android.filament:gltfio-android:$filament")
    implementation("com.google.android.filament:filament-utils-android:$filament")
}
