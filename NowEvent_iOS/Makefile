TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e

INSTALL_TARGET_PROCESSES = NowEvent

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = NowEvent
NowEvent_FILES = $(wildcard Sources/*.m)
NowEvent_FRAMEWORKS = UIKit Foundation CoreGraphics AudioToolbox AVFoundation SafariServices
NowEvent_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error
NowEvent_CODESIGN_FLAGS = -Sentitlements.xml

include $(THEOS_MAKE_PATH)/application.mk

after-stage::
	mkdir -p $(THEOS_STAGING_DIR)/Applications/NowEvent.app
	cp -r Resources/* $(THEOS_STAGING_DIR)/Applications/NowEvent.app/ 2>/dev/null || true
