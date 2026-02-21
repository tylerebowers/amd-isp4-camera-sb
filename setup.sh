#!/bin/bash
# Download and setup AMD ISP4 driver for current kernel + (optional) Secure Boot MOK setup
set -e


MOK_KEY_DIR_DEFAULT="$HOME/.module-signing"
MOK_KEY_DIR="${MOK_KEY_DIR:-$MOK_KEY_DIR_DEFAULT}"

MOK_CERT_CN="${MOK_CERT_CN:-amd_capture kernel module signing}"

KVER="${1:-$(uname -r)}"
TARGET_DIR="linux-$KVER"
MSG_ID="20260212083426.216430-1-Bin.Du@amd.com"

MOK_PRIV="$MOK_KEY_DIR/MOK.priv"
MOK_PEM="$MOK_KEY_DIR/MOK.pem"
MOK_DER="$MOK_KEY_DIR/MOK.der"

secureboot_enabled() {
    command -v mokutil >/dev/null 2>&1 || return 1
    mokutil --sb-state 2>/dev/null | grep -qi 'enabled'
}

ensure_mok_keys_and_enrollment() {
    if ! secureboot_enabled; then
        echo "Secure Boot not enabled (or mokutil not available); skipping MOK key setup."
        return 0
    fi
    if ! command -v mokutil >/dev/null 2>&1; then
        echo "ERROR: mokutil is required for Secure Boot module signing but is not installed."
        echo "Install it (Fedora): sudo dnf install mokutil"
        exit 1
    fi
    if ! command -v openssl >/dev/null 2>&1; then
        echo "ERROR: openssl is required to generate a signing keypair but is not installed."
        echo "Install it (Fedora): sudo dnf install openssl"
        exit 1
    fi

    mkdir -p "$MOK_KEY_DIR"

    # create keypair if missing
    if [[ ! -f "$MOK_PRIV" || ! -f "$MOK_PEM" || ! -f "$MOK_DER" ]]; then
        echo "Creating MOK signing keypair in: $MOK_KEY_DIR"
        umask 077
        openssl req -new -x509 -newkey rsa:2048 \
            -keyout "$MOK_PRIV" -out "$MOK_PEM" -nodes -days 3650 \
            -subj "/CN=${MOK_CERT_CN}/"
        openssl x509 -outform DER -in "$MOK_PEM" -out "$MOK_DER"
        chmod 600 "$MOK_PRIV" || true
    else
        echo "Found existing MOK keypair in: $MOK_KEY_DIR"
    fi

    echo "$MOK_DER"

    # check if key is already enrolled
    out="$(sudo mokutil --test-key "$MOK_DER" 2>&1)" || rc=$?
    if echo "$out" | grep -qi 'already enrolled'; then
        echo "MOK key is already enrolled."
        return 0
    fi

    echo "Secure Boot is enabled and your MOK key is NOT enrolled yet."
    echo "Queuing enrollment now (one-time). You will be prompted for a password."
    sudo mokutil --import "$MOK_DER"

    echo
    echo "============================================================"
    echo "MOK enrollment request queued."
    echo "NEXT STEPS:"
    echo "  1) Reboot"
    echo "  2) In the MOK manager screen: Enroll MOK -> select key -> enter password"
    echo "  3) After reboot, rerun: make install"
    echo "============================================================"
    echo

    exit 2
}

ensure_mok_keys_and_enrollment

if [[ -f "$TARGET_DIR/.patched" ]]; then
    echo "Already set up for $KVER"
    exit 0
fi

echo "Setting up AMD ISP4 driver for kernel $KVER..."

mkdir -p "$TARGET_DIR"
b4 am -l "$MSG_ID"
mkdir -p src/drivers/media/platform/amd/isp4
cd src && git init && git apply --include='drivers/media/platform/amd/isp4/*' ../v8_*.mbx
cd ..
cp src/drivers/media/platform/amd/isp4/*.c src/drivers/media/platform/amd/isp4/*.h "$TARGET_DIR/"
rm -rf src v8_*.mbx v8_*.cover

cat > "$TARGET_DIR/Makefile" << 'EOF'
KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build

obj-m += amd_capture.o
amd_capture-objs := isp4.o isp4_debug.o isp4_interface.o isp4_subdev.o isp4_video.o

build:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean 2>/dev/null || rm -f *.o *.ko *.mod* Module.symvers modules.order
EOF

touch "$TARGET_DIR/.patched"
echo "Done. Run 'make install' to build and install."
