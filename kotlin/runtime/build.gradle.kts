plugins {
    kotlin("jvm")
    `maven-publish`
}

group = "io.github.jiyimeta"
version = (findProperty("wireletVersion") as String?) ?: "0.0.0-SNAPSHOT"

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
    withSourcesJar()
}

dependencies {
    testImplementation(kotlin("test"))
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
}

tasks.test {
    useJUnitPlatform()
}

publishing {
    publications {
        create<MavenPublication>("runtime") {
            from(components["java"])
            artifactId = "wirelet-runtime"
        }
    }
    // Repositories declared in Phase 4 (publish.yml). Local development
    // uses `publishToMavenLocal`.
}
