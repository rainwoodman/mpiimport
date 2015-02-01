# run with python-mpi.py
# this example demonstrates how to
# import modules on selected (rank 0 in this example) ranks
#

from mpi4py import MPI
import mpiimport
import numpy
import six
import sys

# doesn't matter the ordering
if MPI.COMM_WORLD.rank == 0:
    with mpiimport.disable:
        import matplotlib
        print 'rank 0, matplotlib loaded'

# doesn't matter the ordering
with mpiimport.disable:
    if MPI.COMM_WORLD.rank == 0:
        import scipy
        print 'rank 0, scipy loaded'

if MPI.COMM_WORLD.rank != 0:
    try:
        print scipy
    except NameError as e:
        pass
else:
    print 'scipy is', scipy

print MPI.COMM_WORLD.rank, 'hello'
