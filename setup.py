from distutils.core import setup, Extension
from Cython.Build import cythonize

def myext(*args):
    return Extension(*args, include_dirs=["./"])

extensions = [
        myext("mpiimport.mpiimport", ["src/mpiimport.pyx"]),
        ]

setup(
    name="mpiimport", version="0.1",
    author="Yu Feng",
    description="Python Import via MPI",
    package_dir = {'mpiimport': 'src'},
    install_requires=['cython'],
    packages= ['mpiimport'],
    scripts = ['src/python-mpi.py'],
    ext_modules = cythonize(extensions),
)

