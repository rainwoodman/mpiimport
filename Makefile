CC=mpicc
LDSHARED=$(CC) -shared
PYTHONCONFIG=python-config

# on BlueWaters
# make CC=cc LDSHARED="cc -shared"

# on COMA (CMU)
# make CC=mpiicc LDSHARED="mpiicc -shared"

# on Fedora 19 with openmpi
# make CC=mpicc LDSHARED="mpicc -shared"
# remember use python-mpi.py -I openmpi
# to workaround symbol table issues.

.PHONY: build clean

build: 
	CFLAGS="$(CFLAGS)" LDSHARED="$(LDSHARED)" CC="$(CC)" python setup.py build
	$(CC) -o python-mpi python-mpi.c `$(PYTHONCONFIG) --include --libs`
	mkdir -p bin
	cp build/scripts*/python-mpi.py bin/
	cp build/lib.*/mpiimport/mpisite.py bin/
	cp build/lib.*/mpiimport/mpiimport.so bin/
	cp python-mpi bin/

clean:
	rm -rf build
