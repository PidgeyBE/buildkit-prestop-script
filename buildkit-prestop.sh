#!/bin/sh
#
# https://github.com/seatgeek/buildkit-prestop-script
# Copyright SeatGeek
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script waits for buildkit to finish ongoing build processes before exiting.
#
# It is intended to be used as a pre-stop script in a container that runs buildkit.
# This helps us workaround the issue where buildkit does not allow ongoing builds to
# finish when the container receives a SIGTERM signal: https://github.com/moby/buildkit/issues/4090.
#
# The script works by periodically checking whether any buildx clients are connected
# to buildkitd. If we see an established connection, we assume that there's an ongoing
# build process, so we wait a bit and check again. Once we don't see any established
# connections for a certain number of consecutive checks, we assume that all builds
# have stopped and exit the script, indicating that it's safe to stop the container.
# Because this is a somewhat naive approach that only looks at individual points in time,
# we will check multiple times just to be sure that we're not missing any builds.

# Variables
CHECK_FREQUENCY_MS=500                      # How often we should for running build processes (in milliseconds)
WAIT_UNTIL_NO_BUILDS_SEEN_FOR_X_SECONDS=10  # If no build processes are seen for this many seconds, we assume that all builds have stopped
BUILDKITD_PORT=1234                         # Port on which buildkitd is listening for buildx clients

# Calculate the number of checks required based on the wait time and sleep period
REQUIRED_CHECK_COUNT=$((WAIT_UNTIL_NO_BUILDS_SEEN_FOR_X_SECONDS * 1000 / CHECK_FREQUENCY_MS))

# How many consecutive times we've seen no running builds
times=0

# Function to print a message conditionally based on DEBUG environment variable
print_debug() {
    if [ -n "$DEBUG" ]; then
        echo "$1"
    fi
}

echo "Waiting for build processes to finish..."

# Loop until we see zero active connections REQUIRED_CHECK_COUNT consecutive times
while true; do
    ACTIVE_CONNECTIONS=$(netstat -tnp | grep buildkitd | grep ":${BUILDKITD_PORT}" | grep -c ESTABLISHED)
    print_debug "Active connections to buildkitd: $ACTIVE_CONNECTIONS"
    if [ "$ACTIVE_CONNECTIONS" -gt 0 ]; then
        times=0
    else
        times=$((times + 1))
        if [ "$times" -ge "$REQUIRED_CHECK_COUNT" ]; then
            break
        fi
    fi
    usleep $CHECK_FREQUENCY_MS"000"  # Sleep for CHECK_FREQUENCY_MS milliseconds before checking again
done

echo "All build processes seem to have stopped. Exiting now."
