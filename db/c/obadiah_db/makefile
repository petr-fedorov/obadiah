OBJS = obadiah_db.o spread.o 
POSTGRES = /usr/pgsql-11-devel
CXXFLAGS = -Wall -std=c++14 -fPIC -g -I$(POSTGRES)/include/server -D ELOGS=1

libobadiah_db.so: $(OBJS) 
	g++ -shared  $(OBJS)  -o libobadiah_db.so

obadiah_db.o: spi_allocator.h spread.h
spread.o: spread.h

.PHONY: install clean 
install: 
	sudo cp libobadiah_db.so $(POSTGRES)/lib/

clean:
	rm *.o *.so
