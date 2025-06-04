#!/bin/bash

tasks=(
    "iosArm64Klib"
    "iosSimulatorArm64Klib"
    "iosX64Klib"
    "linuxArm64Klib"
    "linuxX64Klib"
    "macosArm64Klib"
    "macosX64Klib"
    "mingwX64Klib"
    "tvosArm64Klib"
    "tvosSimulatorArm64Klib"
    "tvosX64Klib"
    "watchosArm32Klib"
    "watchosArm64Klib"
    "watchosSimulatorArm64Klib"
    "watchosX64Klib"
)

for task in "${tasks[@]}"; do
    echo "Building :kmqtt-common:$task"
    ./gradlew :kmqtt-common:$task

    echo "Building :kmqtt-client:$task"
    ./gradlew :kmqtt-client:$task
done