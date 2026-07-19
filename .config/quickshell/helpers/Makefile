CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra

auth: auth.c
	$(CC) $(CFLAGS) -o auth auth.c -lpam

.PHONY: clean
clean:
	rm -f auth
