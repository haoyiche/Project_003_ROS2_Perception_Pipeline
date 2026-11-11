#!/usr/bin/env bash
# T01 v2: positive and expected-negative ROS2 C++ pub/sub checks.
# Exit codes describe the TEST HARNESS, not a deliberately stopped ROS2 node:
#   0 = test expectation satisfied (including wrong-topic mode)
#   1 = behavioral assertion failed
#   2 = environment or ROS graph setup failed
#   3 = a tested node exited unexpectedly
set -Eeo pipefail

for setup_file in /opt/ros/jazzy/setup.bash "$HOME/ai_lab_project003_colcon/install/local_setup.bash"; do
  if [[ ! -r "$setup_file" ]]; then
    echo "FAIL_ENV: missing ROS setup: $setup_file" >&2
    exit 2
  fi
  if ! source "$setup_file"; then
    echo "FAIL_ENV: failed loading ROS setup: $setup_file" >&2
    exit 2
  fi
done
set -u

MODE="${1:-normal}"
if [[ "$MODE" != "normal" && "$MODE" != "wrong-topic" ]]; then
  echo "USAGE: bash test_r1_pubsub_basic_v2.sh [normal|wrong-topic]" >&2
  exit 2
fi

# Keep this test away from the default ROS domain. Do not launch other
# test instances on the same domain simultaneously.
export ROS_DOMAIN_ID=67
PROJECT="/mnt/d/AI_Lab/02_Projects/Project_003_ROS2_Perception_Pipeline"
BIN="$HOME/ai_lab_project003_colcon/install/l3_r1_cpp/lib/l3_r1_cpp"
for exe in l3_talker l3_listener; do
  if [[ ! -x "$BIN/$exe" ]]; then
    echo "FAIL_ENV: missing executable: $BIN/$exe" >&2
    exit 2
  fi
done
command -v setsid >/dev/null || { echo 'FAIL_ENV: setsid missing' >&2; exit 2; }
command -v ros2 >/dev/null || { echo 'FAIL_ENV: ros2 missing' >&2; exit 2; }

ROOT="$PROJECT/experiments/T01_pubsub_auto"
mkdir -p "$ROOT"
RUN_DIR="$(mktemp -d "$ROOT/run_v2_XXXXXXXX")"
LISTENER_LOG="$RUN_DIR/listener.log"
TALKER_LOG="$RUN_DIR/talker.log"
LISTENER_GRAPH="$RUN_DIR/listener_graph.log"
TALKER_GRAPH="$RUN_DIR/talker_graph.log"
TOPIC_CORRECT="$RUN_DIR/topic_correct.log"
TOPIC_WRONG="$RUN_DIR/topic_wrong.log"
LISTENER_PID=''
TALKER_PID=''

cleanup() {
  local code=$?
  trap - EXIT INT TERM
  for pid in "$LISTENER_PID" "$TALKER_PID"; do
    if [[ -n "$pid" ]]; then
      # setsid starts each process as leader of a private session/process group.
      kill -TERM -- "-$pid" 2>/dev/null || true
    fi
  done
  # Bound shutdown time. Fall back to SIGKILL if a node ignores SIGTERM.
  for _ in {1..20}; do
    local still_running=0
    for pid in "$LISTENER_PID" "$TALKER_PID"; do
      if [[ -n "$pid" ]] && node_alive "$pid"; then
        still_running=1
      fi
    done
    (( still_running == 0 )) && break
    sleep 0.1
  done
  for pid in "$LISTENER_PID" "$TALKER_PID"; do
    if [[ -n "$pid" ]] && node_alive "$pid"; then
      kill -KILL -- "-$pid" 2>/dev/null || true
    fi
  done
  [[ -z "$LISTENER_PID" ]] || wait "$LISTENER_PID" 2>/dev/null || true
  [[ -z "$TALKER_PID" ]] || wait "$TALKER_PID" 2>/dev/null || true
  echo "ARTIFACT_DIR=$RUN_DIR"
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Check both existence and non-zombie state. A PID alone does not prove that
# a subscriber is processing messages.
node_alive() {
  local pid="$1" state
  state="$(ps -o stat= -p "$pid" 2>/dev/null || true)"
  [[ -n "$state" && "$state" != Z* ]]
}

fail_if_dead() {
  if ! node_alive "$LISTENER_PID"; then
    echo "FAIL_NODE_EXIT: listener stopped unexpectedly" >&2
    tail -n 25 "$LISTENER_LOG" >&2 || true
    exit 3
  fi
  if ! node_alive "$TALKER_PID"; then
    echo "FAIL_NODE_EXIT: talker stopped unexpectedly" >&2
    tail -n 25 "$TALKER_LOG" >&2 || true
    exit 3
  fi
}

listener_args=()
expected_topic='/l3/chatter'
if [[ "$MODE" == wrong-topic ]]; then
  listener_args=(--ros-args -r /l3/chatter:=/l3/chatter_wrong)
  expected_topic='/l3/chatter_wrong'
fi

# Run actual installed C++ binaries (not ros2 run wrappers), one process group each.
setsid "$BIN/l3_listener" "${listener_args[@]}" > "$LISTENER_LOG" 2>&1 &
LISTENER_PID=$!
setsid "$BIN/l3_talker" > "$TALKER_LOG" 2>&1 &
TALKER_PID=$!
echo "MODE=$MODE"
echo "ROS_DOMAIN_ID=$ROS_DOMAIN_ID"
echo "LISTENER_PID=$LISTENER_PID TALKER_PID=$TALKER_PID"

# First prove both expected ROS graph interfaces exist. Unlike "no publisher"
# text, the remapped topic is a positive and inspectable fault signature.
graph_ok=0
ready_deadline=$((SECONDS + 15))
while (( SECONDS < ready_deadline )); do
  fail_if_dead
  if ros2 node info /l3_listener > "$LISTENER_GRAPH" 2>&1 &&
     ros2 node info /l3_talker > "$TALKER_GRAPH" 2>&1 &&
     grep -Fq "    $expected_topic: std_msgs/msg/String" "$LISTENER_GRAPH" &&
     grep -Fq '    /l3/chatter: std_msgs/msg/String' "$TALKER_GRAPH"; then
    graph_ok=1
    break
  fi
  sleep 0.25
done
if (( graph_ok == 0 )); then
  echo "FAIL_GRAPH: expected node interfaces not discovered" >&2
  cat "$LISTENER_GRAPH" "$TALKER_GRAPH" >&2 2>/dev/null || true
  exit 2
fi

# Both endpoints must be present on the intended topics. Exact counts catch
# other publishers/subscribers accidentally interfering with the experiment.
if ! ros2 topic info /l3/chatter > "$TOPIC_CORRECT" 2>&1; then
  echo 'FAIL_GRAPH: /l3/chatter not queryable' >&2
  exit 2
fi
if ! grep -Fxq 'Publisher count: 1' "$TOPIC_CORRECT"; then
  echo 'FAIL_GRAPH: expected exactly one /l3/chatter publisher' >&2
  cat "$TOPIC_CORRECT" >&2
  exit 2
fi
if [[ "$MODE" == normal ]]; then
  if ! grep -Fxq 'Subscription count: 1' "$TOPIC_CORRECT"; then
    echo 'FAIL_GRAPH: expected exactly one /l3/chatter subscriber' >&2
    cat "$TOPIC_CORRECT" >&2
    exit 2
  fi
else
  if ! grep -Fxq 'Subscription count: 0' "$TOPIC_CORRECT"; then
    echo 'FAIL_GRAPH: unexpected subscriber on /l3/chatter' >&2
    cat "$TOPIC_CORRECT" >&2
    exit 2
  fi
  if ! ros2 topic info /l3/chatter_wrong > "$TOPIC_WRONG" 2>&1 ||
     ! grep -Fxq 'Publisher count: 0' "$TOPIC_WRONG" ||
     ! grep -Fxq 'Subscription count: 1' "$TOPIC_WRONG"; then
    echo 'FAIL_GRAPH: wrong-topic graph does not match expected 0/1' >&2
    cat "$TOPIC_WRONG" >&2 2>/dev/null || true
    exit 2
  fi
fi

echo "GRAPH_ASSERTION_PASS: $expected_topic"
EXPECTED="Received count: 5, data: 'RGBD ready'"
if [[ "$MODE" == normal ]]; then
  deadline=$((SECONDS + 12))
  while (( SECONDS < deadline )); do
    fail_if_dead
    if grep -Fq "$EXPECTED" "$LISTENER_LOG"; then
      echo 'PASS_NORMAL: expected callback observed; nodes alive'
      exit 0
    fi
    sleep 0.2
  done
  echo 'FAIL_ASSERTION: normal mode did not receive expected data' >&2
  tail -n 25 "$LISTENER_LOG" >&2 || true
  exit 1
fi

# A correct wrong-topic case stays alive but NEVER sees business messages.
# Do not require "no publisher" or "topic not found" text: a silent ROS2
# subscriber with a valid, unmatched subscription need not log either.
observe_deadline=$((SECONDS + 5))
while (( SECONDS < observe_deadline )); do
  fail_if_dead
  if grep -Fq 'Received count:' "$LISTENER_LOG"; then
    echo 'FAIL_ASSERTION: listener unexpectedly received data on remapped topic' >&2
    exit 1
  fi
  sleep 0.2
done
fail_if_dead
echo 'PASS_EXPECTED_NO_MESSAGE: topic mismatch proven; nodes stayed alive; no callback logs for 5s'
exit 0
