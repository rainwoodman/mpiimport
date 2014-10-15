CC=mpicc
LDSHARED=mpicc -shared

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
	mkdir -p bin
	cp build/scripts*/python-mpi.py bin/
	cp build/lib.*/mpiimport/mpisite.py bin/
	cp build/lib.*/mpiimport/mpiimport.so bin/
clean:
	rm -rf build


