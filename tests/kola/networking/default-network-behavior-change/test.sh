#!/bin/bash
## kola:
##   tags: "platform-independent"
##   exclusive: false
##   description: Verify the default networking configurations match expected
##     results.
#
# Since we depend so much on the default networking configurations let's
# alert ourselves when any default networking configuration changes in
# NetworkManager. This allows us to react and adjust to the changes
# (if needed) instead of finding out later that problems were introduced.
# some context in: https://github.com/coreos/fedora-coreos-tracker/issues/1000

set -xeuo pipefail

# shellcheck disable=SC1091
. "$KOLA_EXT_DATA/commonlib.sh"

# EXPECTED_INITRD_NETWORK_CFG1
#   - used on Fedora 37+, scos and RHEL 9.2+
EXPECTED_INITRD_NETWORK_CFG1="# Created by nm-initrd-generator
[connection]
id=Wired Connection
uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
type=ethernet
autoconnect-priority=-100
autoconnect-retries=1
multi-connect=3
[ethernet]
[ipv4]
dhcp-timeout=90
method=auto
required-timeout=20000
[ipv6]
dhcp-timeout=90
method=auto
[proxy]
[user]
org.freedesktop.NetworkManager.origin=nm-initrd-generator"

# EXPECTED_REALROOT_NETWORK_CFG1:
#   - used on all Fedora 37+, scos and RHEL 9.2+
EXPECTED_REALROOT_NETWORK_CFG1="[connection]
id=Wired connection 1
uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
type=ethernet
autoconnect-priority=-999
interface-name=xxxx
timestamp=xxxxxxxxxx
[ethernet]
[ipv4]
method=auto
[ipv6]
addr-gen-mode=default
method=auto
[proxy]
[.nmmeta]
nm-generated=true"

# Function that will remove unique (per-run) data from a connection file
# and also delete any blank lines.
normalize_connection_file() {
    sed -e s/^uuid=.*$/uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/ \
        -e s/^timestamp=.*$/timestamp=xxxxxxxxxx/                 \
        -e s/^interface-name=.*$/interface-name=xxxx/             \
        -e /^$/d                                                  \
        "${1}"
}

source /etc/os-release
if [ "$ID" == "fedora" ]; then
    if [ "$VERSION_ID" -ge "37" ]; then
        EXPECTED_INITRD_NETWORK_CFG=$EXPECTED_INITRD_NETWORK_CFG1
        EXPECTED_REALROOT_NETWORK_CFG=$EXPECTED_REALROOT_NETWORK_CFG1
    else
        fatal "fail: not operating on expected OS version"
    fi
elif [[ "${ID}" = "rhel" ]] || [[ "${ID_LIKE}" =~ "rhel" ]]; then
    if is_scos || is_rhcos; then
        EXPECTED_INITRD_NETWORK_CFG=$EXPECTED_INITRD_NETWORK_CFG1
        EXPECTED_REALROOT_NETWORK_CFG=$EXPECTED_REALROOT_NETWORK_CFG1
    else
        fatal "fail: not operating on expected OS version"
    fi
else
    fatal "fail: not operating on expected OS"
fi


# Execute nm-initrd-generator against our default kargs (defined by
# afterburn drop in) to get the generated initrd network config.
DEFAULT_KARGS_FILE=/usr/lib/dracut/modules.d/35coreos-network/50-afterburn-network-kargs-default.conf
source <(grep -o 'AFTERBURN_NETWORK_KARGS_DEFAULT=.*' $DEFAULT_KARGS_FILE)
tmpdir=$(mktemp -d)
/usr/libexec/nm-initrd-generator \
    -c "${tmpdir}/connections" \
    -i "${tmpdir}/initrd-data-dir" \
    -r "${tmpdir}/conf.d" \
    -- $AFTERBURN_NETWORK_KARGS_DEFAULT
GENERATED_INITRD_NETWORK_CFG=$(normalize_connection_file \
                               "${tmpdir}/connections/default_connection.nmconnection")

# Diff the outputs and fail if the expected doesn't match the generated.
if ! diff -u <(echo "$EXPECTED_INITRD_NETWORK_CFG") <(echo "$GENERATED_INITRD_NETWORK_CFG"); then
    fatal "fail: the expected initrd network config is not given by the kargs"
fi

# Check the default NetworkManager runtime generated connection profile in
# the real root to make sure it matches what we expect.
GENERATED_REALROOT_NETWORK_CFG=$(normalize_connection_file \
                                 <(sudo cat "/run/NetworkManager/system-connections/Wired connection 1.nmconnection"))
if ! diff -u <(echo "$EXPECTED_REALROOT_NETWORK_CFG") <(echo "$GENERATED_REALROOT_NETWORK_CFG"); then
    fatal "fail: the expected realroot network config is not given by the kargs"
fi
ok "success: expected network configs were generated"
