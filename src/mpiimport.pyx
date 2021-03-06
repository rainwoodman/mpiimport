include "libmpi.pxd"
import cPickle

bytescomm = 0
import traceback
cdef class Comm(object):
    cdef MPI_Comm comm
    cdef readonly int rank
    cdef readonly int size

    def barrier(self):
        MPI_Barrier(self.comm)

    def bcast(self, obj, root=0):
        global bytescomm
        cdef int n
        cdef bytes buf

        if self.rank == root:
            buf = cPickle.dumps(obj, 2)
            n = len(buf)
        MPI_Bcast(&n, 1, MPI_INT, root, self.comm)
        bytescomm = bytescomm + n
        if self.rank != root:
            buf = bytes(' ' * n)

        MPI_Bcast(<char*>buf, n, MPI_BYTE, root, self.comm)
        return cPickle.loads(buf)
cdef bind(MPI_Comm comm):
    self = Comm()
    self.comm = comm
    MPI_Comm_rank(self.comm, &self.rank)
    MPI_Comm_size(self.comm, &self.size)
    return self

cdef int provided = MPI_THREAD_MULTIPLE
cdef int initialized
MPI_Initialized(&initialized)
if not initialized:
    MPI_Init_thread(NULL, NULL, provided, &provided)

COMM_WORLD = bind(MPI_COMM_WORLD)

import imp
import sys
import posix

__all__ = ['install', 'COMM_WORLD']

_tmpdir = '/tmp'
_tmpfiles = []
d = {
        imp.PY_SOURCE: "source",
        imp.PY_COMPILED: "compiled",
        imp.PKG_DIRECTORY: "pkg",
        imp.C_BUILTIN: "builtin",
        imp.C_EXTENSION: "extension",
        imp.PY_FROZEN: "frozen"}

blacklist = []

cdef class Profiler:
    cdef readonly double time
    cdef readonly object title
    cdef double now
    cdef int count
    def __init__(self, name):
        self.title = name
        self.time = 0
        self.count = 0
    def start(self):
        self.now = MPI_Wtime()
    def end(self):
        self.time += MPI_Wtime() - self.now
        self.count = self.count + 1
    def __str__(self):
        return '%s: %g (%d)' % (self.title, self.time, self.count)

tio = Profiler('IO')
tload = Profiler('LOAD')
tloadlocal = Profiler('LOADDirect')
tfind = Profiler('FIND')
tcomm = Profiler('COMM')
tloadfile = Profiler('LOADFile')
tall = Profiler('ALL')

def tempnam(dir, prefix, suffix):
    l = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
    s = posix.urandom(16)
    u = ''.join([l[ord(a) % len(l)] for a in s])
    return dir + '/' + prefix + u + suffix

def mkstemp(dir='', suffix='', prefix='', mode='w+', fmode=0600):
    i = 0
    while i < 100:
        fn = tempnam(dir, prefix, suffix)
        try:
            fd = posix.open(fn, posix.O_CREAT | posix.O_EXCL, fmode)
        except OSError:
            i = i + 1
            continue
        f = open(fn, mode)
        posix.close(fd)
        return f
    raise OSError("failed to create a tempfile");

def loadcextensionfromstring(fullname, string, pathname, description):
#    try:
        tio.start()
        with mkstemp(dir=_tmpdir, prefix=fullname.split('.')[-1] + '-', suffix=description[0]) as file:
            file.write(string)
            _tmpfiles.append(file.name)
            name = file.name
        tio.end()

        if _verbose:
            print 'module', fullname, 'using', name, pathname, 'via mpi'

        #with open(name, mode=description[1]) as f2:
        tio.start()
        f2 = open(name, mode=description[1])
        tio.end()
        #print file, pathname, description
        tload.start()
        mod = imp.load_module(fullname, f2, name, description)
        tload.end()
        if description[-1] == imp.C_EXTENSION:
            # important to hold a handle
            # to avoid the system unlinking the file
            # while the module is in use
            mod.filehandle = f2
        else:
            f2.close()
        #print mod
        tio.start()
        # unlink when the module is unloaded
        posix.unlink(name)
        tio.end()
        return mod 
#    except Exception as e:
#        print 'exception', e

def abort():
    """ abort """
    MPI_Abort(MPI_COMM_WORLD, -1)


if hasattr(sys, 'exitfunc'):
    oldexitfunc = sys.exitfunc
else:
    oldexitfunc = lambda : None

def finalize():
    cdef int initialized
    if 'mpi4py' in sys.modules:
        return
    MPI_Initialized(&initialized)
    if initialized:
        MPI_Finalize()

def _cleanup():
    finalize()
    oldexitfunc()
    return

sys.exitfunc = _cleanup

class DummyLoader(object):
    def __init__(self, module):
        self.module = module
    def load_module(self, fullname):
        mod = sys.modules.setdefault(fullname, self.module)
        return self.module

class Loader(object):
    def __init__(self, file, pathname, description):
        self.file = file
        self.pathname = pathname
        self.description = description
    def load_module(self, fullname):
        collective = not _disjoint and not (fullname in blacklist)
        if collective and self.file:
            if self.description[-1] == imp.PY_SOURCE:
                mod = sys.modules.setdefault(fullname,imp.new_module(fullname))
                mod.__file__ = self.pathname
                mod.__package__ = fullname.rpartition('.')[0]
                if _verbose:
                    print 'module', fullname, 'using ', len(self.file), 'bytes', 'PY_SOURCE'
                code = compile(self.file, self.pathname, 'exec', 0, 1)
                exec code in mod.__dict__
#                mod = loadcextensionfromstring(fullname, self.file, self.pathname, self.description) 
            elif self.description[-1] == imp.C_EXTENSION:
                if _verbose:
                    print 'module', fullname, 'using ', len(self.file), 'bytes', 'C_EXTENSION'
                #print "loading extension"
                mod = loadcextensionfromstring(fullname, self.file, self.pathname, self.description) 
            elif False: # use the file=None branch
                   # this doesn't work #self.description[-1] == imp.PKG_DIRECTORY:
                mod = sys.modules.setdefault(fullname, imp.new_module(fullname))
                mod.__path__ = []
                mod.__file__ = "<%s>" % self.__class__.__name__
                mod.__package__ = fullname
                # mod thought it is in-tree
                if _verbose:
                    print 'module', fullname, 'using ', len(self.file), 'bytes', 'PY_SOURCE'
                code = compile(self.file, "", 'exec', 0, 1)
                exec code in mod.__dict__
#                mod = loadcextensionfromstring(fullname, self.file, self.pathname, self.description) 

            else:
                if _verbose:
                    print 'module', fullname, 'using', self.file, 'OTHER'
                tio.start()
                self.file = open(self.file, self.description[1])
                tio.end()
                tloadfile.start()
                mod = imp.load_module(fullname, self.file, self.pathname, self.description)
                tloadfile.end()
        else:
            if _verbose:
                print 'module', fullname, 'using', self.file, 'LOCAL'
            tloadlocal.start()
            mod = imp.load_module(fullname, self.file, self.pathname, self.description)
            tloadlocal.end()
        mod.__loader__ = self
        return mod
def _try_attr(names):
    parent = '.'.join(names[:-1])
    if parent in sys.modules \
            and hasattr(sys.modules[parent], names[-1]):
        return DummyLoader(getattr(sys.modules[parent], names[-1]))
    return None

class Finder(object):
    def __init__(self, comm):
        self.comm = comm
        self.rank = comm.rank
    def find_module(self, fullname, path=None):
        file, pathname, description = None, None, None
        names = fullname.split('.')

        collective = not _disjoint and not (fullname in blacklist)
        if not collective:
            return None
        dummy =  _try_attr(names)
        if dummy: return dummy

        name = names[-1]
        if self.rank == 0 or not collective:
            tfind.start()
            try:
                #print self.rank, 'trying to load', name
                file, pathname, description = imp.find_module(name, path)
            except ImportError as e:
                #print self.rank, 'failed to load', fullname, name, e, path
                file = e
            tfind.end()
        if collective:
            # at this point, only rank 0 has the triplet
            # we prepare to broadcast the content
            #print fullname, file, pathname
            if self.rank == 0:
                if not isinstance(file, Exception):
                    tio.start()
                    if description[-1] == imp.PY_SOURCE:
                        #print 'finding python module', file.name
                        s = file.read()
                        file.close()
                        file = s
                    elif description[-1] == imp.C_EXTENSION:
                        #print 'finding extension', file.name
                        s = file.read()
                        file.close()
                        file = s
                    elif description[-1] == imp.PKG_DIRECTORY:
                        pass
                        # PKG_DIRECTORY doesn't work yet.
                        # print 'PKG:finding file by name', d[description[-1]], pathname, description
                        #file = pathname + "/__init__.py"
                        #try:
                        #    file = open(file, 'r')
                        #    s = file.read()
                        #    file.close()
                        #    file = s
                        #except OSError:
                        #    file = ImportError("file %s not exist" %  file)
                    else:
                        #print 'finding file by name', d[description[-1]]
                        if file:
                            file = file.name
                        else:
                            pass

                    tio.end()
                else:
                    if _verbose:
                        print 'Warning: failed to find module', name, fullname, file, pathname, description, 'at', path

            # ready to broadcast
            tcomm.start()
            file, pathname, description = self.comm.bcast((file, pathname, description))
            tcomm.end()

        if isinstance(file, Exception):
            #print 'Warning: failed to load', name, fullname, file, pathname, description, 'at', path
            # we do not return None, which would fall back to python
            raise file
        return Loader(file, pathname, description)

def install(comm=COMM_WORLD, tmpdir='/tmp', verbose=False, disable=False):
    tall.start()
    global _tmpdir
    global _verbose
    global _disjoint
    _verbose = verbose or int(posix.environ.get('PYTHON_MPIIMPORT_VERBOSE', 0)) == 1
    _disjoint = disable
    _tmpdir = tmpdir
    sys.meta_path.append(Finder(comm))

    if sys.flags.no_site:
        import mpisite as site
        sys.modules['site'] = site
        site.main0()

        import sysconfig
        import _sysconfigdata
        import re

        #if comm.rank == 0:
        site.main1()

        # to hang on matched imports
        comm.barrier()
        sys.path = comm.bcast(sys.path)
        site.main2()

class Disjoint(object):
    def __init__(self):
        pass
    def __enter__(self):
        stop()
    def __exit__(self, type, value, traceback):
        resume()

def stop():
    global _disjoint
    _disjoint = True
def resume():
    global _disjoint
    _disjoint = False

disjoint = Disjoint()
