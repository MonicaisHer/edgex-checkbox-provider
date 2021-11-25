#!/bin/bash -e

if [ "$(id -u)" != "0" ]; then
    echo "script must be run as root"
    exit 1
fi

# get the directory of this script
# snippet from https://stackoverflow.com/a/246128/10102404
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# load the generic utils
# shellcheck source=/dev/null
source "$(dirname "$SCRIPT_DIR")/utils.sh"

snap_check_svcs()
{
    if [ "$1" = "--notfatal" ]; then
        FATAL=0
    else
        FATAL=1
    fi

    # group services by status

    check_enabled_services \
        `#core services` \
        "redis \
        core-data \
        core-command \
        core-metadata \
        `#security services` \
        kong-daemon postgres vault consul 
        `#one-shot security services` \
        security-proxy-setup \
        security-secretstore-setup \
        security-bootstrapper-redis \
        security-consul-bootstrapper "

    check_active_services \
        `#core services` \
        "redis \
        core-data \
        core-command \
        core-metadata \
        `#security services` \
        kong-daemon postgres vault consul"

    check_disabled_services \
        `#app service, kuiper and device-virtual`\
        "app-service-configurable kuiper device-virtual \
        `#support services, system service` \
        support-notifications \
        support-scheduler \
        sys-mgmt-agent"

    check_inactive_services \
        `#app service, kuiper and device-virtual `\
        "app-service-configurable kuiper device-virtual \
        `#one-shot security services` \
        security-proxy-setup \
        security-secretstore-setup \
        security-bootstrapper-redis \
        security-consul-bootstrapper \
        `#support services, system service` \
        support-notifications \
        support-scheduler \
        sys-mgmt-agent"    
}

# wait for services to come online
# NOTE: this may have to be significantly increased on arm64 or low RAM platforms
# to accomodate time for everything to come online
snap_wait_all_services_online()
{
    http_error_code_regex="4[0-9][0-9]|5[0-9][0-9]"
    all_services_online=false
    i=0

    while [ "$all_services_online" = "false" ];
    do
        echo "waiting for all services to come online. Current retry count: $i/300"
        #max retry avoids forever waiting
        ((i=i+1))
        if [ "$i" -ge 300 ]; then
            echo "services timed out, reached max retry count of 300"
            exit 1
        fi

        #dial services
        core_data_status_code=$(curl --insecure --silent --include \
            --connect-timeout 2 --max-time 5 \
            --output /dev/null --write-out "%{http_code}" \
            -X GET 'http://localhost:59880/api/v2/ping') || true
        core_metadata_status_code=$(curl --insecure --silent --include \
            --connect-timeout 2 --max-time 5 \
            --output /dev/null --write-out "%{http_code}" \
            -X GET 'http://localhost:59881/api/v2/ping') || true
        core_command_status_code=$(curl --insecure --silent --include \
            --connect-timeout 2 --max-time 5 \
            --output /dev/null --write-out "%{http_code}" \
            -X GET 'http://localhost:59882/api/v2/ping') || true

        #error status 4xx/5xx will fail the test immediately
        if [[ $core_data_status_code =~ $http_error_code_regex ]] \
            || [[ $core_metadata_status_code =~ $http_error_code_regex ]] \
            || [[ $core_command_status_code =~ $http_error_code_regex ]]; then
            echo "core service(s) received status code 4xx or 5xx"
            exit 1
        fi

        if [[ "$core_data_status_code" == 200 ]] \
            && [[ "$core_metadata_status_code" == 200 ]] \
            && [[ "$core_command_status_code" == 200 ]] \
            && snap_wait_port_status 8000 open \
            && snap_wait_port_status 8200 open \
            && snap_wait_port_status 8500 open \
            && snap_wait_port_status 5432 open \
            && snap_wait_port_status 6379 open; then
            all_services_online=true
            echo "all services up"
        else
            sleep 1
        fi
    done
}

