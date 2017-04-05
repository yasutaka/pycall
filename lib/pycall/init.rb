module PyCall
  private_class_method def self.__initialize_pycall__
    initialized = (0 != PyCall::LibPython.Py_IsInitialized())
    return if initialized

    PyCall::LibPython.Py_InitializeEx(0)

    FFI::MemoryPointer.new(:pointer, 1) do |argv|
      argv.write_pointer(FFI::MemoryPointer.from_string(""))
      PyCall::LibPython.PySys_SetArgvEx(0, argv, 0)
    end
  end
  __initialize_pycall__
end
