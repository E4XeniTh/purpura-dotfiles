CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra

all: auth cava_bridge

auth: auth.c
	$(CC) $(CFLAGS) -o auth auth.c -lpam

# libcava is LukashonakV/cava's fork (github.com/LukashonakV/cava) built
# as a shared library via its meson build - its pkgconfig module is
# named "libcava" (see that repo's meson.build: pkg.generate(...,
# filebase: 'libcava')), not "cava" or "cavacore".
cava_bridge: cava_bridge.c
	$(CC) $(CFLAGS) -o cava_bridge cava_bridge.c $$(pkg-config --cflags --libs libcava libpulse-simple)

.PHONY: all clean
clean:
	rm -f auth cava_bridge
