pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositories {
        google()        // AGP artifacts (gradle-api 8.7.x)
        mavenCentral()
    }
}

rootProject.name = "wirelet"

include(":runtime")
include(":conformance-tests")
include(":gradle-plugin")
include(":observable-runtime")
