module PyCall
  private_class_method def self.__initialize_pycall__
    initialized = (0 != PyCall::LibPython.Py_IsInitialized())
    return if initialized

    PyCall::LibPython.Py_InitializeEx(0)

    FFI::MemoryPointer.new(:pointer, 1) do |argv|
      argv.write_pointer(FFI::MemoryPointer.from_string(""))
      PyCall::LibPython.PySys_SetArgvEx(0, argv, 0)
    end

    @global_table = {}
    @global_table[:builtins] = PyCall.import_module(PYTHON_VERSION < '3.0.0' ? '__builtin__' : 'builtins').__pyobj__

    main_module = PyCall.import_module('__main__').__pyobj__
    @global_table[:__main__] = main_module
    @global_table[:__main_dict__] = PyCall::LibPython.Py_IncRef(LibPython.PyModule_GetDict(main_module))

    at_exit do
      @global_table.each_value do |pyptr|
        pyptr.copy!(PyPtr.null)
      end
    end
  end

  __initialize_pycall__

  def self.builtins
    @global_table[:builtins]
  end

  def self.__main__
    @global_table[:__main__]
  end

  def self.__main_dict__
    @global_table[:__main_dict__]
  end
end
