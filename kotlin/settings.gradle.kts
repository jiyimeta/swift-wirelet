pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositories {
        mavenCentral()
    }
}

rootProject.name = "wirelet"

include(":runtime")
include(":conformance-tests")
include(":gradle-plugin")
include(":observable-runtime")
