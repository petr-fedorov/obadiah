OBJS = obadiah_db.o
POSTGRES = /usr/pgsql-11-devel
CXXFLAGS = -v -Wall -std=c++14 -fPIC -g -I$(POSTGRES)/include/server -D ELOGS=0

libobadiah_db.so: $(OBJS) 
	g++ -shared  $(OBJS)  -o libobadiah_db.so

obadiah_db.o: spi_allocator.h

.PHONY: install
install: 
	sudo cp libobadiah_db.so $(POSTGRES)/lib/

