CC=mpicc
LDSHARED=mpicc -shared
.PHONY: build clean
build: 
	CFLAGS="$(CFLAGS)" LDSHARED="$(LDSHARED)" CC="$(CC)" python setup.py build
	mkdir -p bin
	cp build/scripts*/python-mpi.py bin/
	cp build/lib.*/mpiimport/mpisite.py bin/
	cp build/lib.*/mpiimport/mpiimport.so bin/
clean:
	rm -rf build


