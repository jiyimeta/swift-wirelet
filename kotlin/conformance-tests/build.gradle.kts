// Cross-language conformance tests (Task 2.14).
//
// Decodes the .bin fixtures under fixtures/ — produced by Swift — using
// Kotlin codecs auto-generated from Tests/ConformanceTests/FixtureSchemas.swift.
// Asserts the same field-value invariants as Swift's runner, then
// re-encodes and verifies byte-equality.

plugins {
    kotlin("jvm")
}

// Same group/version as runtime — local-only module, never published.
group = "io.github.jiyimeta"

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

dependencies {
    implementation(project(":runtime"))
    implementation(project(":observable-runtime"))
    testImplementation(kotlin("test"))
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
}

// Wire root for resolving paths into the wirelet Swift package.
val wireletRoot: File = rootDir.parentFile // kotlin/.. = wirelet repo root

sourceSets["main"].kotlin.srcDirs("src/main/kotlin", "build/generated/wirelet")

// Generate codecs from FixtureSchemas.swift before compiling Kotlin.
val generateCodecs by tasks.registering(Exec::class) {
    description = "Run emit-wirelet-kotlin against Tests/ConformanceTests/FixtureSchemas.swift"
    val outputDir = layout.buildDirectory.dir("generated/wirelet").get().asFile
    val sourceDir = File(wireletRoot, "Tests/ConformanceTests")
    val configFile = File(projectDir, "kotlin-codegen.json")
    inputs.dir(sourceDir).withPropertyName("schemaSource")
    inputs.file(configFile).withPropertyName("codegenConfig")
    outputs.dir(outputDir).withPropertyName("generatedCodecs")
    // No --include-package: the source dir contains only the conformance
    // schemas, so emit everything. (--include-package filters by Kotlin
    // codec package, not by Swift module name.)
    commandLine(
        "swift",
        "run",
        "--package-path",
        wireletRoot.absolutePath,
        "emit-wirelet-kotlin",
        "--config",
        configFile.absolutePath,
        "--source",
        sourceDir.absolutePath,
        "--output",
        outputDir.absolutePath,
    )
    doFirst { outputDir.mkdirs() }
}

tasks.matching { it.name.startsWith("compile") && it.name.endsWith("Kotlin") }
    .configureEach { dependsOn(generateCodecs) }

tasks.test {
    useJUnitPlatform()
    // Resolve fixtures/ relative to this module's directory.
    workingDir = projectDir
}
