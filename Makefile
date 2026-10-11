TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64 arm64e

THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = IconSizeFix
IconSizeFix_FILES = Tweak.x
IconSizeFix_CFLAGS = -fobjc-arc -O2
IconSizeFix_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += IconSizeFixPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk