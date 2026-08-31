INSTALL_TARGET_PROCESSES = AlightMotion

ARCHS = arm64
TARGET = iphone:clang:14.5:14.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = AlightMotionAutoExport
ifeq ($(BUILD_B),1)
# Build B: dylib-load-only diagnostic (no registry, hooks, or feature code).
AlightMotionAutoExport_FILES = Tweak_BuildB_Minimal.m
else
# Default production candidate: startup-safe full implementation.
AlightMotionAutoExport_FILES = Tweak_Full_Protected.m
endif
# Startup-safe default: global UIKit hooks remain disabled until a physical
# A/B run proves them safe. Set HOOKS=1 only for an isolated hook A/B build.
ifeq ($(HOOKS),1)
AlightMotionAutoExport_CFLAGS = -fobjc-arc -Wno-error -Wno-unused-variable -Wno-unused-function -DUM_ENABLE_UIKIT_HOOKS=1
else
AlightMotionAutoExport_CFLAGS = -fobjc-arc -Wno-error -Wno-unused-variable -Wno-unused-function -DUM_ENABLE_UIKIT_HOOKS=0
endif
ifeq ($(CRASH_REPORTING),1)
AlightMotionAutoExport_CFLAGS += -DUM_ENABLE_CRASH_REPORTING=1
endif
AlightMotionAutoExport_FRAMEWORKS = UIKit UserNotifications Photos QuartzCore AudioToolbox AVFoundation CoreMedia CoreImage VideoToolbox Metal MetalKit

include $(THEOS_MAKE_PATH)/library.mk
