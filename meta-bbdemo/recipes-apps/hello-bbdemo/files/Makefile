CC ?= gcc
CFLAGS ?= -Wall -Wextra -O2
LDFLAGS ?=

hello-bbdemo: hello-bbdemo.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm -f hello-bbdemo

.PHONY: clean

