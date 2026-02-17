CC = cc
CFLAGS = -O2 -Wall
LDFLAGS = -lsqlite3 -lssl -lcrypto

# On macOS with Homebrew
CFLAGS += $(shell pkg-config --cflags openssl 2>/dev/null)
LDFLAGS += $(shell pkg-config --libs openssl 2>/dev/null)

booking-api: main.c cJSON.c cJSON.h
	$(CC) $(CFLAGS) -o booking-api main.c cJSON.c $(LDFLAGS)

clean:
	rm -f booking-api
