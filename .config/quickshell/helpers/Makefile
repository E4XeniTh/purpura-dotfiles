CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra

all: auth cava_bridge

auth: auth.c
	$(CC) $(CFLAGS) -o auth auth.c -lpam

# cavacore has no pkg-config file on Arch (the dev package, AUR's
# libcava-git, only installs the header + .so) - only libpulse-simple
# goes through pkg-config, cavacore is linked directly.
cava_bridge: cava_bridge.c
	$(CC) $(CFLAGS) -o cava_bridge cava_bridge.c $$(pkg-config --cflags --libs libpulse-simple) -lcavacore

.PHONY: all clean
clean:
	rm -f auth cava_bridge
