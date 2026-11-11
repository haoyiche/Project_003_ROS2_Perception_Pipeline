#!/usr/bin/env bash
set -Eeo pipefail

source /opt/ros/jazzy/setup.bash
source "$HOME/ai_lab_project003_colcon/install/local_setup.bash"
set -u

MODE="${1:-normal}"
if [[ "$MODE" != "normal" && "$MODE" != "wrong-topic" ]]; then
    echo "USAGE: bash test_r1_pubsub_basic.sh [normal|wrong-topic]" >&2
    exit 2
fi

# This test uses a separate ROS domain to avoid unrelated running nodes.
export ROS_DOMAIN_ID=67
PROJECT="/mnt/d/AI_Lab/02_Projects/Project_003_ROS2_Perception_Pipeline"
BIN="$HOME/ai_lab_project003_colcon/install/l3_r1_cpp/lib/l3_r1_cpp"
for executable in l3_talker l3_listener; do
    [[ -x "$BIN/$executable" ]] || {
        echo "FAIL: missing executable: $BIN/$executable" >&2
        exit 2
    }
done

ROOT="$PROJECT/experiments/T01_pubsub_auto"
mkdir -p "$ROOT"
RUN_DIR="$(mktemp -d "$ROOT/run_XXXXXXXX")"
LISTENER_LOG="$RUN_DIR/listener.log"
TALKER_LOG="$RUN_DIR/talker.log"
TALKER_PID=""
LISTENER_PID=""

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    for pid in "$TALKER_PID" "$LISTENER_PID"; do
        if [[ -n "$pid" ]]; then
            kill -TERM -- "-$pid" 2>/dev/null || true
        fi
    done
    if [[ -n "$TALKER_PID" ]]; then
        wait "$TALKER_PID" 2>/dev/null || true
    fi
    if [[ -n "$LISTENER_PID" ]]; then
        wait "$LISTENER_PID" 2>/dev/null || true
    fi
    printf 'ARTIFACT_DIR=%s\n' "$RUN_DIR"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

listener_args=()
if [[ "$MODE" == "wrong-topic" ]]; then
    listener_args=(--ros-args -r /l3/chatter:=/l3/chatter_wrong)
fi

setsid "$BIN/l3_listener" "${listener_args[@]}" > "$LISTENER_LOG" 2>&1 &
LISTENER_PID=$!
setsid "$BIN/l3_talker" > "$TALKER_LOG" 2>&1 &
TALKER_PID=$!

echo "MODE=$MODE"
echo "LISTENER_PID=$LISTENER_PID TALKER_PID=$TALKER_PID"
echo "ROS_DOMAIN_ID=$ROS_DOMAIN_ID"

deadline=$((SECONDS + 12))
while (( SECONDS < deadline )); do
    if grep -Fq "Received count: 5, data: 'RGBD ready'" "$LISTENER_LOG"; then
        if kill -0 "$LISTENER_PID" 2>/dev/null && kill -0 "$TALKER_PID" 2>/dev/null; then
            echo "PASS: listener received 5 matching messages"
            exit 0
        fi
        echo "FAIL: expected data found, but a process exited" >&2
        exit 1
    fi
    if ! kill -0 "$LISTENER_PID" 2>/dev/null || ! kill -0 "$TALKER_PID" 2>/dev/null; then
        echo "FAIL: a node exited before the assertion" >&2
        cat "$LISTENER_LOG" >&2
        cat "$TALKER_LOG" >&2
        exit 1
    fi
    sleep 0.2
done

echo "FAIL: timeout waiting for the expected callback log" >&2
cat "$LISTENER_LOG" >&2
exit 1
