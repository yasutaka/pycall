#ifndef PYCALL_EXT_H
#define PYCALL_EXT_H 1

#include <ruby/ruby.h>

#ifndef UNLIKELY
# define UNLIKELY(x) x
#endif

#include "ruby-ffi.h"

#include <inttypes.h>

typedef intptr_t Py_intptr_t;

#ifdef HAVE_SSIZE_T
typedef ssize_t Py_ssize_t;
#elif SIZEOF_VOID_P == SIZEOF_SIZE_T
typedef Py_intptr_t Py_ssize_t;
#error
# error "Python needs a typedef for Py_ssize_t in pyport.h."
#endif

/* NOTE: Currently pycall do not support Py_TRACE_REFS-enabled Python */
#define _PyObject_HEAD_EXTRA

typedef struct PyObjectStruct {
  _PyObject_HEAD_EXTRA;
  Py_ssize_t const ob_refcnt;  /* This should be const. */
  /* ... */
} PyObject;

#endif /* PYCALL_EXT_H */
