ARCHS     = arm64
SDK       = $(shell xcrun --sdk iphoneos --show-sdk-path)
CC        = $(shell xcrun --sdk iphoneos --find clang)
MIN_IOS   = 15.0

CFLAGS    = -arch $(ARCHS) \
            -isysroot $(SDK) \
            -miphoneos-version-min=$(MIN_IOS) \
            -fobjc-arc \
            -O2 \
            -fvisibility=hidden \
            -framework UIKit \
            -framework Foundation

TARGET    = AimAssist.dylib

all: $(TARGET)

$(TARGET): Sources/AimAssist.m
	$(CC) $(CFLAGS) \
	    -dynamiclib \
	    -install_name @rpath/$(TARGET) \
	    -o $(TARGET) \
	    Sources/AimAssist.m \
	    -lobjc

clean:
	rm -f $(TARGET)
