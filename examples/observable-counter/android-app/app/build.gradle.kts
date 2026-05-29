plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("io.github.jiyimeta.wirelet")
}

android {
    namespace = "io.github.jiyimeta.observablecounter"
    compileSdk = 34

    defaultConfig {
        applicationId = "io.github.jiyimeta.observablecounter"
        // minSdk follows the Swift Android SDK target API: the cross-built
        // .so depends on libc symbols available from android-28.
        minSdk = 28
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets["main"].kotlin.srcDirs("src/main/kotlin")
    sourceSets["androidTest"].kotlin.srcDirs("src/androidTest/kotlin")
}

wirelet {
    // Repo root is four levels up:
    //   examples/observable-counter/android-app/app/  ->  ../../../..
    swiftPackagePath.set(file("../../../.."))

    sources {
        register("main") {
            schemaPaths.from(file("../../swift/Sources/ObservableCounterJNI"))
            codecPackage.set("io.github.jiyimeta.observablecounter")
            modelPackage.set("io.github.jiyimeta.observablecounter")
            emitModels.set(true)
        }
    }

    observable {
        register("main") {
            schemaPaths.from(file("../../swift/Sources/ObservableCounterJNI"))
            viewModelPackage.set("io.github.jiyimeta.observablecounter.generated")
            modelPackage.set("io.github.jiyimeta.observablecounter")
            codecPackage.set("io.github.jiyimeta.observablecounter")
            libraryName.set("ObservableCounterJNI")
        }
    }
}

dependencies {
    implementation("io.github.jiyimeta:wirelet-runtime:0.0.1-local")
    implementation("io.github.jiyimeta:wirelet-observable-runtime:0.0.1-local")

    val composeBom = platform("androidx.compose:compose-bom:2024.10.00")
    implementation(composeBom)
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    androidTestImplementation("androidx.test:core:1.6.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:rules:1.6.1")
}
