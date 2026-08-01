INSTALL_TARGET_PROCESSES = AlightMotion

ARCHS = arm64
TARGET = iphone:clang:14.5:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AlightMotionAutoExport

AlightMotionAutoExport_FILES = Tweak.xm
AlightMotionAutoExport_CFLAGS = -fobjc-arc
AlightMotionAutoExport_FRAMEWORKS = UIKit UserNotifications

include $(THEOS_MAKE_PATH)/tweak.mk
