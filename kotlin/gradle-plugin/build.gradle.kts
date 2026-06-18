plugins {
    `kotlin-dsl`
    `java-gradle-plugin`
    `maven-publish`
}

group = "io.github.jiyimeta"
version = (findProperty("wireletVersion") as String?) ?: "0.0.0-SNAPSHOT"

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
    withSourcesJar()
}

// Functional-test source set runs TestKit fixtures.
val functionalTest by sourceSets.creating

val functionalTestImplementation by configurations.getting {
    extendsFrom(configurations.testImplementation.get())
}

dependencies {
    // AGP API used reflectively to wire generated source dirs into Android
    // variants. `gradle-api` (not `gradle`) is the API-only artifact and
    // matters only at compile time — the consumer brings their own AGP.
    compileOnly("com.android.tools.build:gradle-api:9.2.1")

    testImplementation(kotlin("test"))
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
    functionalTestImplementation(kotlin("test"))
    functionalTestImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
    functionalTestImplementation(gradleTestKit())
}

gradlePlugin {
    plugins {
        create("wireletPlugin") {
            id = "io.github.jiyimeta.wirelet"
            implementationClass = "io.github.jiyimeta.wirelet.gradle.WireletPlugin"
            displayName = "Wirelet Kotlin codegen"
            description = "Generates Kotlin codecs from @WireFormat Swift sources via the emit-wirelet-kotlin CLI."
        }
    }
    testSourceSets(functionalTest)
}

tasks.register<Test>("functionalTest") {
    description = "Runs Gradle TestKit functional tests for the wirelet plugin."
    group = "verification"
    testClassesDirs = functionalTest.output.classesDirs
    classpath = functionalTest.runtimeClasspath
    useJUnitPlatform()
    // Pass the wirelet repo root through to fixtures so they can set
    // `swiftPackagePath` correctly when the plugin DSL is configured.
    systemProperty("wirelet.repoRoot", rootDir.parentFile.absolutePath)
    shouldRunAfter(tasks.test)
}

tasks.check { dependsOn(tasks.named("functionalTest")) }

tasks.test { useJUnitPlatform() }

publishing {
    publications {
        // Gradle's java-gradle-plugin auto-registers a "pluginMaven"
        // publication for the main artifact plus a marker publication
        // for each declared plugin. No manual publication needed.
    }
    repositories {
        maven {
            name = "GitHubPackages"
            url = uri("https://maven.pkg.github.com/jiyimeta/swift-wirelet")
            credentials {
                username = System.getenv("GITHUB_ACTOR")
                password = System.getenv("GITHUB_TOKEN")
            }
        }
    }
}
