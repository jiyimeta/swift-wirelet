plugins {
    kotlin("jvm") version "1.9.22"
    application
}

repositories {
    mavenCentral()
    mavenLocal()
}

dependencies {
    implementation("io.github.jiyimeta:wirelet-runtime:0.0.1-local")
}

sourceSets["main"].kotlin.srcDirs("src/main/kotlin", "build/generated/wirelet")

application {
    mainClass.set("io.github.jiyimeta.wirelet.example.MainKt")
}
