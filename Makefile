LOLHTML_SRC_DIR=lol-html/c-api
LOLHTML_STATIC_LIB=$(LOLHTML_SRC_DIR)/target/release/liblolhtml.a
COMPAT_SRC_DIR=lua-compat-5.3/c-api

all: lolhtml.so

.PHONY: $(LOLHTML_STATIC_LIB)
$(LOLHTML_STATIC_LIB):
	[ -d lol-html ] || ( echo "need to clone submodules" >&2 ; exit 1 )
	cd lol-html/c-api && cargo build --release --locked

lolhtml.o: lolhtml.c
	$(CC) -c -o $@ $(CFLAGS) -Wall -I"$(LOLHTML_SRC_DIR)/include" -I"$(COMPAT_SRC_DIR)" -fPIC $<

lolhtml.so: $(LOLHTML_STATIC_LIB) lolhtml.o
	$(CC) -shared -o $@ -Wall -lpthread \
		   lolhtml.o \
		   -Wl,--whole-archive $(LOLHTML_STATIC_LIB) \
		   -Wl,--no-whole-archive
