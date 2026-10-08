CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra
wicare_daemon: wicare_daemon.c
	$(CC) $(CFLAGS) -o $@ $<
clean:
	rm -f wicare_daemon
