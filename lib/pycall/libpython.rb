require 'ffi'

module PyCall
  module LibPython
    extend FFI::Library

    private_class_method

    def self.find_libpython(python = nil)
      python ||= 'python'
      python_config = investigate_python_config(python)

      v = python_config[:VERSION]
      libprefix = FFI::Platform::LIBPREFIX
      libs = []
      %i(INSTSONAME LDLIBRARY).each do |key|
        lib = python_config[key]
        libs << lib << File.basename(lib) if lib
      end
      if (lib = python_config[:LIBRARY])
        libs << File.basename(lib, File.extname(lib))
      end
      libs << "#{libprefix}python#{v}" << "#{libprefix}python"
      libs.uniq!

      executable = python_config[:executable]
      libpaths = [ python_config[:LIBDIR] ]
      if FFI::Platform.windows?
        libpaths << File.dirname(executable)
      else
        libpaths << File.expand_path('../../lib', executable)
      end
      libpaths << python_config[:PYTHONFRAMEWORKPREFIX] if FFI::Platform.mac?
      exec_prefix = python_config[:exec_prefix]
      libpaths << exec_prefix << File.join(exec_prefix, 'lib')
      libpaths.compact!

      unless ENV['PYTHONHOME']
        # PYTHONHOME tells python where to look for both pure python and binary modules.
        # When it is set, it replaces both `prefix` and `exec_prefix`
        # and we thus need to set it to both in case they differ.
        # This is also what the documentation recommends.
        # However, they are documented to always be the same on Windows,
        # where it causes problems if we try to include both.
        if FFI::Platform.windows?
          ENV['PYTHONHOME'] = exec_prefix
        else
          ENV['PYTHONHOME'] = [python_config[:prefix], exec_prefix].join(':')
        end

        # Unfortunately, setting PYTHONHOME screws up Canopy's Python distribution?
        unless system(python, '-c', 'import site', out: File::NULL, err: File::NULL)
          ENV['PYTHONHOME'] = nil
        end
      end

      # Try LIBPYTHON environment variable first.
      if ENV['LIBPYTHON']
        if File.file?(ENV['LIBPYTHON'])
          begin
            libs = ffi_lib(ENV['LIBPYTHON'])
            return libs.first
          rescue LoadError
          end
        end
        $stderr.puts '[WARN] Ignore the wrong libpython location specified in LIBPYTHON environment variable.'
      end

      # Find libpython (we hope):
      libsuffix = FFI::Platform::LIBSUFFIX
      multiarch = python_config[:MULTIARCH] || python_config[:multiarch]
      dir_sep = File::ALT_SEPARATOR || File::SEPARATOR
      libs.each do |lib|
        libpaths.each do |libpath|
          # NOTE: File.join doesn't use File::ALT_SEPARATOR
          libpath_libs = [ [libpath, lib].join(dir_sep) ]
          libpath_libs << [libpath, multiarch, lib].join(dir_sep) if multiarch
          libpath_libs.each do |libpath_lib|
            [
              libpath_lib,
              "#{libpath_lib}.#{libsuffix}"
            ].each do |fullname|
              next unless File.file?(fullname)
              begin
                libs = ffi_lib(fullname)
                return libs.first
              rescue LoadError
                # skip load error
              end
            end
          end
        end
      end
    end

    def self.investigate_python_config(python)
      python_env = { 'PYTHONIOENCODING' => 'UTF-8' }
      IO.popen(python_env, [python, python_investigator_py], 'r') do |io|
        {}.tap do |config|
          io.each_line do |line|
            key, value = line.chomp.split(': ', 2)
            config[key.to_sym] = value if value != 'None'
          end
        end
      end
    end

    def self.python_investigator_py
      File.expand_path('../python/investigator.py', __FILE__)
    end

    ffi_lib_flags :lazy, :global
    libpython = find_libpython ENV['PYTHON']

    require 'pycall_ext'
    PyPtr.__init__(libpython)

    PyPtr.class_eval do
      extend FFI::DataConverter

      if FFI::TypeDefs.has_key? :uintptr_t
        native_type :uintptr_t
      elsif FFI.type_size(:ulong) == FFI.type_size(:pointer)
        native_type :ulong
      elsif FFI.type_size(:ulong_long) == FFI.type_size(:pointer)
        native_type :ulong_long
      else
        raise "Ruby requires sizeof(long) or sizeof(long_long) is equal to sizeof(void*)"
      end

      def self.from_native(addr, ctx)
        self.new(addr)
      end

      def self.to_native(pyptr, ctx)
        pyptr.__address__
      end

      def self.null
        self.new(FFI::Pointer::NULL)
      end
    end

    # --- global variables ---

    define_singleton_method(:pyglobal) do |name|
      PyPtr.new(libpython.find_variable(name.to_s))
    end

    PyType_Type = pyglobal(:PyType_Type)

    if libpython.find_variable('PyInt_Type')
      has_PyInt_Type = true
      PyInt_Type = pyglobal(:PyInt_Type)
    else
      has_PyInt_Type = false
      PyInt_Type = pyglobal(:PyLong_Type)
    end

    PyLong_Type = pyglobal(:PyLong_Type)
    PyBool_Type = pyglobal(:PyBool_Type)
    PyFloat_Type = pyglobal(:PyFloat_Type)
    PyComplex_Type = pyglobal(:PyComplex_Type)
    PyUnicode_Type = pyglobal(:PyUnicode_Type)

    if libpython.find_symbol('PyString_FromStringAndSize')
      string_as_bytes = false
      PyString_Type = pyglobal(:PyString_Type)
    else
      string_as_bytes = true
      PyString_Type = pyglobal(:PyBytes_Type)
    end

    PyList_Type = pyglobal(:PyList_Type)
    PyTuple_Type = pyglobal(:PyTuple_Type)
    PyDict_Type = pyglobal(:PyDict_Type)
    PySet_Type = pyglobal(:PySet_Type)

    PyFunction_Type = pyglobal(:PyFunction_Type)
    PyMethod_Type = pyglobal(:PyMethod_Type)

    # --- functions ---

    attach_function :Py_GetVersion, [], :string
    attach_function :Py_InitializeEx, [:int], :void
    attach_function :Py_IsInitialized, [], :int
    attach_function :PySys_SetArgvEx, [:int, :pointer, :int], :void

    # Object

    attach_function :PyObject_RichCompare, [PyPtr, PyPtr, :int], PyPtr
    attach_function :PyObject_GetAttrString, [PyPtr, :string], PyPtr
    attach_function :PyObject_SetAttrString, [PyPtr, :string, PyPtr], :int
    attach_function :PyObject_HasAttrString, [PyPtr, :string], :int
    attach_function :PyObject_GetItem, [PyPtr, PyPtr], PyPtr
    attach_function :PyObject_SetItem, [PyPtr, PyPtr, PyPtr], :int
    attach_function :PyObject_DelItem, [PyPtr, PyPtr], :int
    attach_function :PyObject_Call, [PyPtr, PyPtr, PyPtr], PyPtr
    attach_function :PyObject_IsInstance, [PyPtr, PyPtr], :int
    attach_function :PyObject_Dir, [PyPtr], PyPtr
    attach_function :PyObject_Repr, [PyPtr], PyPtr
    attach_function :PyObject_Str, [PyPtr], PyPtr
    attach_function :PyObject_Type, [PyPtr], PyPtr
    attach_function :PyCallable_Check, [PyPtr], :int

    # Bool

    attach_function :PyBool_FromLong, [:long], PyPtr

    # Integer

    if has_PyInt_Type
      attach_function :PyInt_AsSsize_t, [PyPtr], :ssize_t
    else
      attach_function :PyInt_AsSsize_t, :PyLong_AsSsize_t, [PyPtr], :ssize_t
    end

    if has_PyInt_Type
      attach_function :PyInt_FromSsize_t, [:ssize_t], PyPtr
    else
      attach_function :PyInt_FromSsize_t, :PyLong_FromSsize_t, [:ssize_t], PyPtr
    end

    # Float

    attach_function :PyFloat_FromDouble, [:double], PyPtr
    attach_function :PyFloat_AsDouble, [PyPtr], :double

    # Complex

    attach_function :PyComplex_RealAsDouble, [PyPtr], :double
    attach_function :PyComplex_ImagAsDouble, [PyPtr], :double

    # String

    if string_as_bytes
      attach_function :PyString_FromStringAndSize, :PyBytes_FromStringAndSize, [:string, :ssize_t], PyPtr
    else
      attach_function :PyString_FromStringAndSize, [:string, :ssize_t], PyPtr
    end

    # PyString_AsStringAndSize :: (PyPtr, char**, int*) -> int
    if string_as_bytes
      attach_function :PyString_AsStringAndSize, :PyBytes_AsStringAndSize, [PyPtr, :pointer, :pointer], :int
    else
      attach_function :PyString_AsStringAndSize, [PyPtr, :pointer, :pointer], :int
    end

    # Unicode

    # PyUnicode_DecodeUTF8
    case
    when libpython.find_symbol('PyUnicode_DecodeUTF8')
      attach_function :PyUnicode_DecodeUTF8, [:string, :ssize_t, :string], PyPtr
    when libpython.find_symbol('PyUnicodeUCS4_DecodeUTF8')
      attach_function :PyUnicode_DecodeUTF8, :PyUnicodeUCS4_DecodeUTF8, [:string, :ssize_t, :string], PyPtr
    when libpython.find_symbol('PyUnicodeUCS2_DecodeUTF8')
      attach_function :PyUnicode_DecodeUTF8, :PyUnicodeUCS2_DecodeUTF8, [:string, :ssize_t, :string], PyPtr
    end

    # PyUnicode_AsUTF8String
    case
    when libpython.find_symbol('PyUnicode_AsUTF8String')
      attach_function :PyUnicode_AsUTF8String, [PyPtr], PyPtr
    when libpython.find_symbol('PyUnicodeUCS4_AsUTF8String')
      attach_function :PyUnicode_AsUTF8String, :PyUnicodeUCS4_AsUTF8String, [PyPtr], PyPtr
    when libpython.find_symbol('PyUnicodeUCS2_AsUTF8String')
      attach_function :PyUnicode_AsUTF8String, :PyUnicodeUCS2_AsUTF8String, [PyPtr], PyPtr
    end

    # Tuple

    attach_function :PyTuple_New, [:ssize_t], PyPtr
    attach_function :PyTuple_GetItem, [PyPtr, :ssize_t], PyPtr
    attach_function :PyTuple_SetItem, [PyPtr, :ssize_t, PyPtr], :int
    attach_function :PyTuple_Size, [PyPtr], :ssize_t

    # Slice

    attach_function :PySlice_New, [PyPtr, PyPtr, PyPtr], PyPtr

    # List

    attach_function :PyList_New, [:ssize_t], PyPtr
    attach_function :PyList_Size, [PyPtr], :ssize_t
    attach_function :PyList_GetItem, [PyPtr, :ssize_t], PyPtr
    attach_function :PyList_SetItem, [PyPtr, :ssize_t, PyPtr], :int
    attach_function :PyList_Append, [PyPtr, PyPtr], :int

    # Sequence

    attach_function :PySequence_Size, [PyPtr], :ssize_t
    attach_function :PySequence_GetItem, [PyPtr, :ssize_t], PyPtr
    attach_function :PySequence_Contains, [PyPtr, PyPtr], :int

    # Dict

    attach_function :PyDict_New, [], PyPtr
    attach_function :PyDict_GetItem, [PyPtr, PyPtr], PyPtr
    attach_function :PyDict_GetItemString, [PyPtr, :string], PyPtr
    attach_function :PyDict_SetItem, [PyPtr, PyPtr, PyPtr], :int
    attach_function :PyDict_SetItemString, [PyPtr, :string, PyPtr], :int
    attach_function :PyDict_DelItem, [PyPtr, PyPtr], :int
    attach_function :PyDict_DelItem, [PyPtr, :string], :int
    attach_function :PyDict_Size, [PyPtr], :ssize_t
    attach_function :PyDict_Keys, [PyPtr], PyPtr
    attach_function :PyDict_Values, [PyPtr], PyPtr
    attach_function :PyDict_Items, [PyPtr], PyPtr
    attach_function :PyDict_Contains, [PyPtr, PyPtr], :int

    # Set

    attach_function :PySet_Size, [PyPtr], :ssize_t
    attach_function :PySet_Contains, [PyPtr, PyPtr], :int
    attach_function :PySet_Add, [PyPtr, PyPtr], :int
    attach_function :PySet_Discard, [PyPtr, PyPtr], :int

    # Module

    attach_function :PyModule_GetDict, [PyPtr], PyPtr

    # Import

    attach_function :PyImport_ImportModule, [:string], PyPtr

    # Operators

    attach_function :PyNumber_Add, [PyPtr, PyPtr], PyPtr
    attach_function :PyNumber_Subtract, [PyPtr, PyPtr], PyPtr
    attach_function :PyNumber_Multiply, [PyPtr, PyPtr], PyPtr
    attach_function :PyNumber_TrueDivide, [PyPtr, PyPtr], PyPtr
    attach_function :PyNumber_Power, [PyPtr, PyPtr, PyPtr], PyPtr

    # Compiler

    attach_function :Py_CompileString, [:string, :string, :int], PyPtr
    attach_function :PyEval_EvalCode, [PyPtr, PyPtr, PyPtr], PyPtr

    # Error

    attach_function :PyErr_Clear, [], :void
    attach_function :PyErr_Print, [], :void
    attach_function :PyErr_Occurred, [], PyPtr
    attach_function :PyErr_Fetch, [:pointer, :pointer, :pointer], :void
    attach_function :PyErr_NormalizeException, [:pointer, :pointer, :pointer], :void

    public_class_method
  end

  PYTHON_DESCRIPTION = LibPython.Py_GetVersion().freeze
  PYTHON_VERSION = PYTHON_DESCRIPTION.split(' ', 2)[0].freeze
end
