#!/bin/bash -e

# get the directory of this script
# snippet from https://stackoverflow.com/a/246128/10102404
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# load the utils
# shellcheck source=/dev/null
source "$SCRIPT_DIR/utils.sh"

snap_remove

# install the snap to make sure it installs
if [ -n "$REVISION_TO_TEST" ]; then
    snap_install "$REVISION_TO_TEST" "$REVISION_TO_TEST_CHANNEL" "$REVISION_TO_TEST_CONFINEMENT"
else
    snap_install edgexfoundry beta 
fi

# wait for services to come online
# NOTE: this may have to be significantly increased on arm64 or low RAM platforms
# to accomodate time for everything to come online
sleep 120

# start device-virtual
snap start edgexfoundry.device-virtual

# wait 10 seconds - check to make sure it's still running
sleep 10
if [ -n "$(snap services edgexfoundry.device-virtual | grep edgexfoundry.device-virtual | grep inactive)" ]; then
    echo "failed to start device-virtual"
    exit 1
fi

echo -n "finding jq... "

set +e
if command -v edgexfoundry.jq > /dev/null; then
    JQ=$(command -v edgexfoundry.jq)
elif command -v jq > /dev/null; then
    JQ=$(command -v jq)
else
    echo "NOT FOUND"
    echo "install with \`snap install jq\`"
    exit 1
fi

echo "found at $JQ"

# check to see if we can find the device created by device-virtual
while true; do
    if ! (edgexfoundry.curl -s localhost:48081/api/v1/device | $JQ '.'); then
        # not json - something's wrong
        echo "invalid JSON response from core-metadata"
        exit 1
    elif [ "$(edgexfoundry.curl -s localhost:48081/api/v1/device | $JQ 'map(select(.name == "Random-Boolean-Generator01")) | length')" -lt 1 ]; then
        # no devices yet, keep waiting
        sleep 1
    else
        # got the device, break out
        break
    fi
done

# check to see if we can get a reading from the Random-Boolean-Generator01
while true; do
    if ! (edgexfoundry.curl -s localhost:48080/api/v1/reading/device/Random-Boolean-Generator01/10 | $JQ '.'); then
        # not json - something's wrong
        echo "invalid JSON response from core-data"
        exit 1
    elif [ "$(edgexfoundry.curl -s localhost:48080/api/v1/reading/device/Random-Boolean-Generator01/10 | $JQ 'length')" -le 1 ]; then
        # no readings yet, keep waiting
        sleep 1
    else
        # got at least one reading, break out
        break
    fi
done
set -e

# remove the snap to run the next test
snap_remove