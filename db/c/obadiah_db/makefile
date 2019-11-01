OBJS = obadiah_db.o spread.o 
POSTGRES = /usr/pgsql-11
TARGET=libobadiah_db.so
CXXFLAGS = -Wall -std=c++14 -fPIC -g -I$(POSTGRES)/include/server -D DEBUG_DEPTH=0 -D DEBUG_SPREAD=0

$(TARGET):$(OBJS) 
	g++ -shared  $(OBJS)  -o $(TARGET)

obadiah_db.o: spi_allocator.h spread.h
spread.o: spread.h

.PHONY: install clean 
install: 
	sudo cp $(TARGET) $(POSTGRES)/lib/

clean:
	rm *.o *.so
