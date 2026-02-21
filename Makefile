# AMD ISP4 Camera Driver
KVER ?= $(shell uname -r)
TARGET_DIR := linux-$(KVER)

KDIR ?= /lib/modules/$(KVER)/build
SIGN_FILE := $(KDIR)/scripts/sign-file
SIGN_KEY  ?= $(HOME)/.module-signing/MOK.priv
SIGN_CERT ?= $(HOME)/.module-signing/MOK.pem

.PHONY: all install clean setup sign

all: setup
	$(MAKE) -C $(TARGET_DIR) build

sign: all
	@if [ ! -x "$(SIGN_FILE)" ]; then \
		echo "ERROR: sign-file not found at $(SIGN_FILE) (install kernel-devel/kernel headers)"; \
		exit 1; \
	fi
	@if [ ! -f "$(SIGN_KEY)" ] || [ ! -f "$(SIGN_CERT)" ]; then \
		echo "ERROR: signing key/cert missing: $(SIGN_KEY) / $(SIGN_CERT)"; \
		exit 1; \
	fi
	"$(SIGN_FILE)" sha256 "$(SIGN_KEY)" "$(SIGN_CERT)" "$(TARGET_DIR)/amd_capture.ko"

install: sign
	sudo install -Dm644 $(TARGET_DIR)/amd_capture.ko /lib/modules/$(KVER)/extra/amd_capture.ko
	sudo depmod -a $(KVER)
	-sudo modprobe -r amd_capture 2>/dev/null
	sudo modprobe amd_capture
	echo "amd_capture" | sudo tee /etc/modules-load.d/amd-camera.conf >/dev/null
	echo "Check via v4l2:"
	v4l2-ctl --list-devices

clean:
	-$(MAKE) -C $(TARGET_DIR) clean

setup:
	@./setup.sh $(KVER)
