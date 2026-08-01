INSTALL_TARGET_PROCESSES = AlightMotion

ARCHS = arm64
TARGET = iphone:clang:14.5:14.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = AlightMotionAutoExport
AlightMotionAutoExport_FILES = Tweak.m
AlightMotionAutoExport_CFLAGS = -fobjc-arc
AlightMotionAutoExport_FRAMEWORKS = UIKit UserNotifications AVFoundation

include $(THEOS_MAKE_PATH)/library.mk
