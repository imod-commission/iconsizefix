TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = IconSizeFixPrefs

IconSizeFixPrefs_FILES = IconSizeFixRootListController.m
IconSizeFixPrefs_FRAMEWORKS = UIKit Foundation
IconSizeFixPrefs_INSTALL_PATH = /Library/PreferenceBundles
IconSizeFixPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk