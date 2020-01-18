LOLHTML_SRC_DIR=lol-html/c-api
LOLHTML_STATIC_LIB=$(LOLHTML_SRC_DIR)/target/release/liblolhtml.a

all: lolhtml.so

.PHONY: $(LOLHTML_STATIC_LIB)
$(LOLHTML_STATIC_LIB):
	[ -d lol-html ] || ( echo "need to clone submodules" >&2 ; exit 1 )
	cd lol-html/c-api && cargo build --release --locked

lolhtml.o: lolhtml.c
	$(CC) -c -Wall -o $@ -I $(LOLHTML_SRC_DIR)/include $<

lolhtml.so: $(LOLHTML_STATIC_LIB) lolhtml.o
	$(CC) -shared -o $@ -Wall -lpthread \
		   lolhtml.o \
		   -Wl,--whole-archive $(LOLHTML_STATIC_LIB) \
		   -Wl,--no-whole-archive
