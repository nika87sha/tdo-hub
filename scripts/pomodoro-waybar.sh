#!/bin/bash
# Waybar module: lee estado del pomodoro daemon

cat /tmp/pomodoro-state 2>/dev/null || echo "{\"text\":\"🍅\",\"class\":\"pomodoro-idle\"}"
