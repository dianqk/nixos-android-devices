# SPDX-License-Identifier: MIT
CC ?= cc
CFLAGS ?= -O2 -g
CFLAGS += -std=c11 -Wall -Wextra -Werror
LDLIBS += -lm

mobile-charger: main.o core.o display.o ui.o
	$(CC) $(LDFLAGS) $^ $(LDLIBS) -o $@

test-controller: test.o core.o
	$(CC) $(LDFLAGS) $^ -lm -o $@

test-input: test-input.o core.o display.o ui.o
	$(CC) $(LDFLAGS) $^ $(LDLIBS) -o $@

test-display: test-display.o core.o ui.o
	$(CC) $(LDFLAGS) $^ $(LDLIBS) -o $@

check: test-controller test-input test-display
	./test-controller
	./test-input
	./test-display

install: mobile-charger
	install -Dm755 mobile-charger $(DESTDIR)$(PREFIX)/bin/mobile-charger

clean:
	rm -f *.o mobile-charger test-controller test-input test-display

.PHONY: check install clean
