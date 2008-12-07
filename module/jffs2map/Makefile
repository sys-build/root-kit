#DEBUG = y

include Rules.make

ifeq ($(DEBUG),y)
  DEBFLAGS = -O -g -DSCULL_DEBUG # "-O" is needed to expand inlines
else
  DEBFLAGS = -O2
endif

CFLAGS += $(DEBFLAGS)
CFLAGS += -DEXPORT_SYMTAB

all: 	jffs2map2.o \
	.depend
clean:
	rm -f *.o *~ core .depend

depend .depend dep:
	$(CC) $(CFLAGS) -M *.c > $@

ifeq (.depend,$(wildcard .depend))
include .depend
endif
