#!/bin/bash

SPOTIFYD_CONFIG="$HOME/.config/spotifyd/spotifyd.conf" # Updated path

check_spotifyd() {
  pgrep -x spotifyd >/dev/null
  return $?
}

start_spotifyd() {
  if ! check_spotifyd; then
    echo "Starting spotifyd with config: $SPOTIFYD_CONFIG"
    if [ ! -f "$SPOTIFYD_CONFIG" ]; then
      echo "Error: Config file not found at $SPOTIFYD_CONFIG"
      return 1
    fi

    # Start spotifyd with verbose output for debugging
    spotifyd --config-path "$SPOTIFYD_CONFIG" --no-daemon --verbose &

    # Give spotifyd time to start and authenticate
    sleep 5

    if check_spotifyd; then
      echo "spotifyd process started"
      # Check if it's actually running and authenticated
      if pgrep -f spotifyd >/dev/null; then
        echo "spotifyd is running and started successfully"
        return 0
      else
        echo "spotifyd process exists but might have authentication issues"
        return 1
      fi
    else
      echo "Failed to start spotifyd"
      return 1
    fi
  else
    echo "spotifyd is already running"
  fi
}

stop_spotifyd() {
  if check_spotifyd; then
    echo "Stopping spotifyd..."
    pkill spotifyd
    sleep 2
    if ! check_spotifyd; then
      echo "spotifyd stopped successfully"
    else
      echo "Failed to stop spotifyd, trying SIGKILL..."
      pkill -9 spotifyd
      sleep 1
      if ! check_spotifyd; then
        echo "spotifyd forcefully stopped"
      else
        echo "Failed to stop spotifyd"
        return 1
      fi
    fi
  else
    echo "spotifyd is not running"
  fi
}

case "$1" in
"start")
  start_spotifyd
  ;;
"stop")
  stop_spotifyd
  ;;
"restart")
  stop_spotifyd
  sleep 2
  start_spotifyd
  ;;
*)
  echo "Usage: $0 {start|stop|restart}"
  exit 1
  ;;
esac
