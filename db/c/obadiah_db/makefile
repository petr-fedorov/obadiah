OBJS = obadiah_db.o spread.o 
POSTGRES = /usr/pgsql-11
BASE=libobadiah_db.so
MAJOR=1
MINOR=1
SONAME=$(BASE).$(MAJOR)
LATEST_RELEASE=$(subst .,,$(suffix $(shell ls -v $(POSTGRES)/lib/$(SONAME).$(MINOR).* 2>/dev/null | tail -n 1)))
RELEASE=$(if $(LATEST_RELEASE),$(shell expr $(LATEST_RELEASE) + 1),1)
TARGET=$(SONAME).$(MINOR).$(RELEASE)
CXXFLAGS = -Wall -std=c++14 -fPIC -g -I$(POSTGRES)/include/server -D DEBUG_DEPTH=0 -D DEBUG_SPREAD=0

$(TARGET):$(OBJS) 
	  $(CXX) -shared  $(OBJS) -Wl,-soname=$(SONAME) -o $(TARGET)

obadiah_db.o: spi_allocator.h spread.h
spread.o: spread.h

.PHONY: install clean

install: 
	sudo cp $(TARGET) $(POSTGRES)/lib/
	sudo ldconfig -n $(POSTGRES)/lib/

clean:
	rm -f $(OBJS) $(BASE)*
