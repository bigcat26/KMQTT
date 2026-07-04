#!/bin/bash
set -euo pipefail

tasks=(
    "iosArm64MainKlibrary"
    "iosSimulatorArm64MainKlibrary"
    "iosX64MainKlibrary"
    "linuxArm64MainKlibrary"
    "linuxX64MainKlibrary"
    "macosArm64MainKlibrary"
    "macosX64MainKlibrary"
    "mingwX64MainKlibrary"
    "tvosArm64MainKlibrary"
    "tvosSimulatorArm64MainKlibrary"
    "tvosX64MainKlibrary"
    "watchosArm32MainKlibrary"
    "watchosArm64MainKlibrary"
    "watchosSimulatorArm64MainKlibrary"
    "watchosX64MainKlibrary"
    "jvmJar"
)

for task in "${tasks[@]}"; do
    echo "Building :kmqtt-common:$task"
    ./gradlew ":kmqtt-common:$task"

    echo "Building :kmqtt-client:$task"
    ./gradlew ":kmqtt-client:$task"
done
