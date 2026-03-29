#!/bin/bash
# Kill all processes using port 4000

PORT=4000

# Find processes using the port
PIDS=$(lsof -ti:$PORT 2>/dev/null)

if [ -z "$PIDS" ]; then
  echo "No processes found on port $PORT"
else
  echo "Terminating processes on port $PORT: $PIDS"
  # Try graceful termination first
  kill $PIDS 2>/dev/null
  sleep 1
  # Force kill if still running
  kill -9 $PIDS 2>/dev/null
  echo "Port $PORT is now free"
fi

