CC=mpicc
.PHONY: build clean
build: 
	CFLAGS=$(CFLAGS) LDSHARED="mpicc -shared" CC="$(CC)" python setup.py build
	mkdir -p bin
	cp build/scripts*/python-mpi.py bin/
	cp build/lib.*/mpiimport/mpisite.py bin/
	cp build/lib.*/mpiimport/mpiimport.so bin/
clean:
	rm -rf build


