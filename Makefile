# AMD ISP4 Camera Driver
KVER ?= $(shell uname -r)
TARGET_DIR := linux-$(KVER)

.PHONY: all sign install clean setup

all: setup
	$(MAKE) -C $(TARGET_DIR) build

sign:
	/usr/src/kernels/$(KVER)/scripts/sign-file sha256 ~/mok/private_key.priv ~/mok/public_key.der $(TARGET_DIR)/amd_capture.ko

install: all sign
	sudo install -Dm644 $(TARGET_DIR)/amd_capture.ko /lib/modules/$(KVER)/extra/amd_capture.ko
	sudo depmod -a $(KVER)
	-sudo modprobe -r amd_capture 2>/dev/null
	sudo modprobe amd_capture
	echo "amd_capture" | sudo tee /etc/modules-load.d/amd-camera.conf >/dev/null

clean:
	-$(MAKE) -C $(TARGET_DIR) clean

setup:
	@./setup.sh $(KVER)
