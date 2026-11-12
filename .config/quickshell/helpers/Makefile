CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra

all: auth cava_bridge idle_inhibit

auth: auth.c
	$(CC) $(CFLAGS) -o auth auth.c -lpam

# libcava is LukashonakV/cava's fork (github.com/LukashonakV/cava) built
# as a shared library via its meson build - its pkgconfig module is
# named "libcava" (see that repo's meson.build: pkg.generate(...,
# filebase: 'libcava')), not "cava" or "cavacore".
cava_bridge: cava_bridge.c
	$(CC) $(CFLAGS) -o cava_bridge cava_bridge.c $$(pkg-config --cflags --libs libcava libpulse-simple)

# The D-Bus side of auto-lock/auto-sleep's "don't go idle" requests (see
# idle_inhibit.c) - sd-bus, from libsystemd (systemd-libs).
idle_inhibit: idle_inhibit.c
	$(CC) $(CFLAGS) -o idle_inhibit idle_inhibit.c $$(pkg-config --cflags --libs libsystemd)

.PHONY: all clean
clean:
	rm -f auth cava_bridge idle_inhibit
