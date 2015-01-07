# Python Import via MPI

One problem with large scale parallel application written in Python is the startup time. The Python
Interpreter may spend before even start processing any useful user logic.

Two factors contribute to the slowness:
 1 At start-up, thousands of file system operations are performed on the centralized shared 
filesystem that hosts the python installation, to resolve and load the modules.
 2 When resolving symbols in a shared object file from extensions can be slow on some platforms.

`mpiimport` aims to address the first issue. We have used `mpiimport` in production 
parallel MPI applications with upto 8,192 MPI ranks on BlueWaters (NCSA), and 576 MPI 
ranks on Edison (NERSC). 

`mpiimport` delegates the file operations to the root rank of `MPI_COMM_WORLD` via a Python import hook.
It significantly reduces the number of filesystem system calls at the
start up of python scripts.

`mpiimport` can improve the startup performance (speed and reliability) of complex 
python scripts on super-computers due to the reduced load on the filesystem.

Note that the gain is very limited if dynamic linking on the system is very slow. (For example, Hopper at NERSC). 

Currently we only implemented `mpiimport` for Python 2.7.

## Installation and usage

`mpiimport` compiles and runs on BlueWaters (NCSA, with bw-python), Edison(NERSC, with python), 
and Rock Clusters 6.4 with Intel MPI. 

To install, clone the source and make
```
    $ git clone http://github.com/rainwoodman/mpiimport
    $ cd mpiimport
    $ make CC=cc LDSHARED=cc
```
Note that on different systems you need to set CC and LDSHARED accordingly.

The binary will be in `bin` directory:
```
    $ ls bin
    mpiimport.so  mpisite.py  MPI.so  python-mpi.py
```

To run your python mpi program with mpiimport, simply replace `python`
with `python-mpi.py`

For example, if the old invocation is
```
    aprun -n 16384 python mymassivepythoncode.py a b c 
```
now we do
```
    aprun -n 16384 python -S bin/python-mpi.py mymassivepythoncode.py a b c 
```
or on systems that supports shebang
```
    mpirun -n 16384 bin/python-mpi.py mymassivepythoncode.py a b c 
```

`python-mpi.py` supports the following arguments:

```
  -I openmpi   : workaround libmpi.so lazy binding issue 
                with openmpi on Fedora and other linux systems;
                not needed with Intel MPI or Cray MPI.
  -c 'command' : execute command (like python -c )
  -v           : verbose; writes out how each module is imported
  -d           : debug mode; all modules are loaded locally; no
                 communication through MPI.
```

We recommend invoking python interpreter running `python-mpi.py` with `-S`, 
since this ensures `mpiimport` is imported at the earliest possible step of the
the interpreter initialization. A different flavor of `site.py` is 
imported, to maintain compatibility to traditional python.

## How it is done

Root rank resolves the qualified module name to a pathname and load
the module into memory (either as script or the binary .so file). The
module content is pickled and broadcast to `MPI_COMM_WORLD`. 

All ranks then either compile and eval the script, or save the .so
file to `/tmp` and load the extension dynamically.

Some similarly motivated work are done by Asher Langton at
https://github.com/langton/MPI_Import; we note that Langton optimizes
the queries to the directory structures only; we optimizes the file
operations as well.

A completely different approach has been attempted by Matthew
Turk (NCSA). Turk builds all extension modules 
into the python interpreter, as builtin modules. The script files
are combined into zip files. Turk's approach requires significant
amount of work to inspect individual packages that are being used by
the scripts; with the most amount of reduction in filesystem syscalls.

## Background and motivation
Python does a lot of file operations upon startup.
This is not an issue for small scale applications -- but on
applications at a massive scale (10K+ MPI ranks), these file
operations become a burden to the shared file system, just like the
shared library burden, described in [Hopper-UG]

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

## Performance on BlueWaters 
Notice that on BlueWaters first aprun in the same partition is always 
faster than the subsequent apruns. This is likely due to time in aprun
to clean up the nodes for running the jobs. In case we reject
significantly faster runs for both mpiimport and python cases.

1. Single node, 32 ranks, 40 runs average, `import numpy`.
   ```
   mpiimport 15.498075     +/- 2.45510705864
   python    19.7058461538 +/- 1.23226379207
   ```
   There is already a measurable improvement on even a single node job.

1. 32 nodes, 1024 ranks, 2 runs, 

   1. 'import numpy.fft'.

       ```
         python      0m31.573s 0m32.939s
         mpiimport   0m32.908s 0m33.478s
       ```
   1. 'import numpy.fft; import scipy.interpolate'

       ```
         python      0m51.268s 0m49.922s
         mpiimport   0m38.913s 0m39.196s
       ```
   We see that for small scale jobs, communication time overshadows
   the gain from reduced amount of IO operations on single ranks.
   
   As we import more modules, we see that mpiimport starts to show its
   effect. The bare speed up is 20%.

1. 128 nodes, 4096 ranks, single run, 'import numpy'.

1. 512 nodes, 16384 ranks, single run, 'import numpy'.
    1. 'import numpy'

        ```
          python     6m56.415s
          mpiimport  2m3.517s
        ```
    1. 'import numpy.fft; import scipy.interpolate'

        ```
          python     8m50.109s
          mpiimport  3m40.979s
        ```
    We do see a large improvement (> 50%) from pure python import.

[Hopper-UG] https://cug.org/proceedings/attendee_program_cug2012/includes/files/pap124.pdf

