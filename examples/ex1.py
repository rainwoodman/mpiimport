# run with python-mpi.py
# this example demonstrates how to
# import modules on selected (rank 0 in this example) ranks
#

from mpi4py import MPI
import numpy
import six
import sys

# doesn't matter the ordering
if MPI.COMM_WORLD.rank == 0:
    with sys.mpiimport.disjoint:
        import matplotlib
        print 'rank 0, matplotlib loaded'

# doesn't matter the ordering
with sys.mpiimport.disjoint:
    if MPI.COMM_WORLD.rank == 0:
        import scipy
        print 'rank 0, scipy loaded'

sys.mpiimport.stop()
if MPI.COMM_WORLD.rank == 0:
    import datetime
    print 'rank 0, datetime loaded'
sys.mpiimport.resume()

print MPI.COMM_WORLD.rank, 'hello'
