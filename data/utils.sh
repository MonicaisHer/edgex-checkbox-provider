#!/bin/bash -e

if [ "$(id -u)" != "0" ]; then
    echo "script must be run as root"
    exit 1
fi

snap_install()
{
    local the_snap=$1
    local the_channel=$2
    local confinement=$3

    if [ "$the_snap" = "edgexfoundry" ]; then
        if [ -n "$confinement" ]; then
            snap install "$the_snap" --channel="$the_channel" "$confinement"
        else
            snap install "$the_snap" --channel="$the_channel"
        fi
    else
        if [ -n "$confinement" ]; then
            snap install "$the_snap" "$confinement"
        else
            snap install "$the_snap"
        fi
    fi
}

snap_refresh()
{
    local the_snap=$1
    local the_channel=$2
    local confinement=$3

    if [ "$the_snap" = "edgexfoundry" ]; then
        if [ -n "$confinement" ]; then
            snap refresh "$the_snap" --channel="$the_channel" "$confinement"
        else
            snap refresh "$the_snap" --channel="$the_channel"
        fi
    else
        # for refreshing a file snap we need to use install
        # but snapd still treats it like a refresh
        if [ -n "$confinement" ]; then
            snap install "$the_snap" "$confinement"
        else
            snap install "$the_snap"
        fi
    fi
}

check_enabled_services()
{
    for svc in $1; do
        svcStatus="$(snap services edgexfoundry.$svc | grep $svc | awk '{print $2}')"
        if [ "enabled" != "$svcStatus" ]; then
            echo "service $svc has status \"$svcStatus\" but should be enabled"
            if [ "$FATAL" = "1" ]; then
                exit 1
            fi
        fi
    done
}

# all the core-* services, security-services, consul, and redis
# except security-*-setup as those are all oneshot daemons
check_active_services()
{
    for svc in $1; do
        svcStatus="$(snap services edgexfoundry.$svc | grep $svc | awk '{print $3}')"
        if [ "active" != "$svcStatus" ]; then
            echo "service $svc has status \"$svcStatus\" but should be active"
            if [ "$FATAL" = "1" ]; then
                exit 1
            fi
        fi
    done
}

check_disabled_services()
{
    for svc in $1; do
        svcStatus="$(snap services edgexfoundry.$svc | grep $svc | awk '{print $2}')"
        if [ "disabled" != "$svcStatus" ]; then
            echo "service $svc has status \"$svcStatus\" but should be disabled"
            if [ "$FATAL" = "1" ]; then
                exit 1
            fi
        fi
    done
}

# all the disabled services + the oneshot daemons
check_inactive_services()
{
    for svc in $1; do
        svcStatus="$(snap services edgexfoundry.$svc | grep $svc | awk '{print $3}')"
        if [ "inactive" != "$svcStatus" ]; then
            echo "service $svc has status \"$svcStatus\" but should be inactive"
            if [ "$FATAL" = "1" ]; then
                exit 1
            fi
        fi
    done
}

get_snap_svc_status()
{
    case "$1" in 
        "status")
            svcStatus="$(snap services edgexfoundry.$1 | grep $1 | awk '{print $3}')"
            ;;
        "")
            ;;
    esac
}

snap_remove()
{
    snap remove edgexfoundry || true
}

