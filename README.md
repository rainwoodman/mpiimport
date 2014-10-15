
# Python Import via MPI

## Installation and usage
    clone the source and make
```
    $ git clone http://github.com/rainwoodman/mpiimport
    $ cd mpiimport
    $ make CC=cc LDSHARED=cc
```

The binary will be in `bin` directory:
```
    $ ls bin
    mpiimport.so  mpisite.py  MPI.so  python-mpi.py
```

To run your python mpi program with mpiimport, simply replace python
with python-mpi.py

For example, if the old invocation is
```
    aprun -n 16384 python mymassivepythoncode.py a b c 
```
now we do
```
    aprun -n 16384 bin/python-mpi.py mymassivepythoncode.py a b c 
```
## Background and motivation
Python does a lot of file operations upon startup.
This is not an issue for small scale applications -- but on
applications at a massive scale (10K+ MPI ranks), these file
operations become a burden to the shared file system.

For example, on a typical python installation with numpy the number of
file operations to 

Do nothing but quit:
```
   $ strace -ff -e file python -c '' 2>&1 |wc -l
   917
```
import numpy.fft:
```
   $ strace -ff -e file python -c 'import numpy.fft' 2>&1 |wc -l
   4557
```
import scipy.interpolate and numpy.fft:
```
   $ strace -ff -e file python -c 'import numpy.fft; import scipy.interpolate' 2>&1|wc -l
   8089
```

Keep in mind that in a massively parallel application, the payload may
in fact only access a few very large files. The overhead here is a
headache.

mpiimport mitigate the issue by delegating most of the file operations
to the root rank of the MPI world; the reset of the world receives the
contents of the modules via MPI\_Bcast.

With mpiimport, 
```
   $ mpirun -np 2 strace -ff -o mpiimport-nothing -e file bin/python-mpi -c 'a=1'
   $ wc -l mpiimport-nothing.*
   1517 mpiimport-nothing.16248
    956 mpiimport-nothing.16250
```
```
   $ mpirun -np 2 strace -ff -o mpiimport-fft -e file bin/python-mpi -c 'import numpy.fft'
   $ wc -l mpiimport-fft.*
    4772 mpiimport-fft.14911
    1194 mpiimport-fft.14913
```
We notice that the non-root rank is doing a lot less file operations.
It gets better with more complicated packages.
```
   $ mpirun -np 2 strace -ff -o mpiimport-interpolate -e file bin/python-mpi.py -I openmpi -c 'import numpy.fft; import scipy.interpolate'
   $ wc -l mpiimport-interpolate.*
   8624 mpiimport-interpolate.16324
   1541 mpiimport-interpolate.16329
```


