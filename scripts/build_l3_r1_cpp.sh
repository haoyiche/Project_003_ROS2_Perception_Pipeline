#!/usr/bin/env bash
set -eo pipefail

source /opt/ros/jazzy/setup.bash

WS="/mnt/d/AI_Lab/02_Projects/Project_003_ROS2_Perception_Pipeline/ros2_ws"
OUT="$HOME/ai_lab_project003_colcon"

echo "=== ENVIRONMENT CHECK ==="
echo "ROS_DISTRO=$ROS_DISTRO"
echo "HOME=$HOME"
echo "WS=$WS"
echo "OUT=$OUT"

if [ ! -f "$WS/src/l3_r1_cpp/CMakeLists.txt" ]; then
    echo "ERROR: ROS2 package not found"
    exit 1
fi

mkdir -p "$OUT"
cd "$OUT"

echo "=== BUILD CUSTOM ROS2 PACKAGE ==="

colcon --log-base "$OUT/log" build \
  --base-paths "$WS/src" \
  --build-base "$OUT/build" \
  --install-base "$OUT/install" \
  --packages-select l3_r1_cpp \
  --event-handlers console_direct+

echo "=== LOAD BUILT PACKAGE ==="
source "$OUT/install/local_setup.bash"

echo "=== CHECK EXECUTABLE ==="
ros2 pkg executables l3_r1_cpp

echo "=== ASSERT EXECUTABLE EXISTS ==="
ros2 pkg executables l3_r1_cpp | grep -Fx "l3_r1_cpp l3_talker"

echo "BUILD_AND_DISCOVERY_CHECK_FINISHED"