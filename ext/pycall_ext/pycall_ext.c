#include "pycall_ext.h"

#include <assert.h>

static VALUE mPyCall;
static VALUE mLibPython;
static VALUE cPyPtr;
static VALUE rbffi_PointerClass;

static ID id_incref;
static ID id_to_ptr;

static PyObject *Py_None;
static void (*Py_IncRef)(PyObject *);
static void (*Py_DecRef)(PyObject *);

enum pyptr_flags {
  PYPTR_NEED_DECREF = 1
};

typedef struct pyptr_struct {
  PyObject *pyobj;
  VALUE flags;
} pyptr_t;

#define PYPTR(p) ((pyptr_t *)(p))
#define PYPTR_PYOBJ(p) (PYPTR(p)->pyobj)
#define PYPTR_FLAGS(p) (PYPTR(p)->flags)

#define PYPTR_DECREF_NEEDED_P(p) (0 != (PYPTR_FLAGS(p) & PYPTR_NEED_DECREF))

static inline int
ffi_pointer_p(VALUE obj)
{
  return CLASS_OF(obj) == rbffi_PointerClass;
}

static void *
ffi_pointer_get_pointer(VALUE obj)
{
  Pointer *ffi_ptr;
  Data_Get_Struct(obj, Pointer, ffi_ptr);
  return ffi_ptr->memory.address;
}

static void
pyptr_mark(void *ptr)
{
}

static void
pyptr_free(void *ptr)
{
  if (PYPTR_PYOBJ(ptr) && PYPTR_DECREF_NEEDED_P(ptr)) {
    Py_DecRef(PYPTR_PYOBJ(ptr));
  }
  xfree(ptr);
}

static size_t
pyptr_memsize(void const *ptr)
{
  return sizeof(pyptr_t);
}

static rb_data_type_t const pyptr_data_type = {
  "pyptr",
  {
    pyptr_mark,
    pyptr_free,
    pyptr_memsize,
  },
  0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
pyptr_alloc(VALUE klass)
{
  pyptr_t *pyptr;
  VALUE obj = TypedData_Make_Struct(klass, pyptr_t, &pyptr_data_type, pyptr);
  pyptr->pyobj = NULL;
  pyptr->flags = 0;
  return obj;
}

static void
pyptr_init(VALUE obj, PyObject *pyobj, int incref, int decref)
{
  pyptr_t *pyptr;

  assert(Py_IncRef != NULL);
  assert(Py_DecRef != NULL);

  TypedData_Get_Struct(obj, pyptr_t, &pyptr_data_type, pyptr);

  pyptr->pyobj = pyobj;

  if (incref) {
    Py_IncRef(pyobj);
  }

  if (decref) {
    pyptr->flags |= PYPTR_NEED_DECREF;
  }
}

static VALUE
pyptr_initialize(int argc, VALUE *argv, VALUE self)
{
  VALUE ptr_like, incref;
  void *address;

  switch (rb_scan_args(argc, argv, "11", &ptr_like, &incref)) {
    case 1:
      incref = Qfalse;
      break;

    default:
      break;
  }

  if (RB_INTEGER_TYPE_P(ptr_like)) {
    address = NUM2VOIDP(ptr_like);
  }
  else if (ffi_pointer_p(ptr_like)) {
ffi_pointer:
    address = ffi_pointer_get_pointer(ptr_like);
  }
  else if (rb_respond_to(ptr_like, id_to_ptr)) {
    ptr_like = rb_funcall2(ptr_like, id_to_ptr, 0, NULL);
    goto ffi_pointer;
  }
  else {
    rb_raise(rb_eTypeError, "The argument must be either Integer or FFI::Pointer-like object.");
  }

  pyptr_init(self, (PyObject *)address, RTEST(incref), 1);

  return self;
}

static VALUE
pyptr_get_refcnt(VALUE self)
{
  pyptr_t *pyptr;
  TypedData_Get_Struct(self, pyptr_t, &pyptr_data_type, pyptr);
  return SSIZET2NUM(PYPTR_PYOBJ(pyptr)->ob_refcnt);
}

static VALUE
pyptr_get_address(VALUE self)
{
  pyptr_t *pyptr;
  TypedData_Get_Struct(self, pyptr_t, &pyptr_data_type, pyptr);
  return rb_uint_new((VALUE)PYPTR_PYOBJ(pyptr));
}

static VALUE
pyptr_is_none(VALUE self)
{
  pyptr_t *pyptr;
  TypedData_Get_Struct(self, pyptr_t, &pyptr_data_type, pyptr);
  return PYPTR_PYOBJ(pyptr) == Py_None ? Qtrue : Qfalse;
}

static VALUE
pyptr_is_null(VALUE self)
{
  pyptr_t *pyptr;
  TypedData_Get_Struct(self, pyptr_t, &pyptr_data_type, pyptr);
  return PYPTR_PYOBJ(pyptr) == NULL ? Qtrue : Qfalse;
}

static void *
find_symbol(VALUE libpython, char const *name)
{
  VALUE sym;

  sym = rb_funcall(libpython, rb_intern("find_symbol"), 1, rb_str_new_cstr(name));
  if (NIL_P(sym)) return NULL;

  return ffi_pointer_get_pointer(sym);
}

static VALUE
pyptr_s_init(VALUE klass, VALUE libpython)
{
  static int initialized = 0;

  if (initialized) return Qfalse;

  Py_IncRef = (void (*)(PyObject *)) find_symbol(libpython, "Py_IncRef");
  Py_DecRef = (void (*)(PyObject *)) find_symbol(libpython, "Py_DecRef");
  Py_None = (PyObject *) find_symbol(libpython, "_Py_NoneStruct");
  Py_IncRef(Py_None);

  initialized = 1;
  return Qtrue;
}

static VALUE
pyptr_s_none(VALUE klass)
{
  VALUE obj = pyptr_alloc(klass);
  pyptr_init(obj, Py_None, 0, 0);
  return obj;
}

static VALUE
libpython_s_incref(VALUE mod, VALUE pyptr_obj)
{
  pyptr_t *pyptr;
  TypedData_Get_Struct(pyptr_obj, pyptr_t, &pyptr_data_type, pyptr);
  Py_IncRef(PYPTR_PYOBJ(pyptr));
  return pyptr_obj;
}

static VALUE
libpython_s_decref(VALUE mod, VALUE pyptr_obj)
{
  pyptr_t *pyptr;
  TypedData_Get_Struct(pyptr_obj, pyptr_t, &pyptr_data_type, pyptr);
  Py_DecRef(PYPTR_PYOBJ(pyptr));
  return pyptr_obj;
}

void
Init_pycall_ext(void)
{
  rb_require("ffi");
  rbffi_PointerClass = rb_path2class("FFI::Pointer");

  mPyCall = rb_define_module("PyCall");
  mLibPython = rb_define_module_under(mPyCall, "LibPython");
  cPyPtr = rb_define_class_under(mLibPython, "PyPtr", rb_cObject);
  rb_define_alloc_func(cPyPtr, pyptr_alloc);
  rb_define_method(cPyPtr, "initialize", pyptr_initialize, -1);
  rb_define_method(cPyPtr, "__refcnt__", pyptr_get_refcnt, 0);
  rb_define_method(cPyPtr, "__address__", pyptr_get_address, 0);
  rb_define_method(cPyPtr, "none?", pyptr_is_none, 0);
  rb_define_method(cPyPtr, "null?", pyptr_is_null, 0);

  rb_define_singleton_method(cPyPtr, "__init__", pyptr_s_init, 1);
  rb_define_singleton_method(cPyPtr, "none", pyptr_s_none, 0);

  rb_define_singleton_method(mLibPython, "Py_IncRef", libpython_s_incref, 1);
  rb_define_singleton_method(mLibPython, "Py_DecRef", libpython_s_decref, 1);

  id_incref = rb_intern("incref");
  id_to_ptr = rb_intern("to_ptr");
}
