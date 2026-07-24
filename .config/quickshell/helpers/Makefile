CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra

all: auth cava_bridge

auth: auth.c
	$(CC) $(CFLAGS) -o auth auth.c -lpam

cava_bridge: cava_bridge.c
	$(CC) $(CFLAGS) -o cava_bridge cava_bridge.c $$(pkg-config --cflags --libs libpulse-simple cava)

.PHONY: all clean
clean:
	rm -f auth cava_bridge
