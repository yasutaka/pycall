module PyCall
  module Types
    def self.pyisinstance(pyobj, pytype)
      pyobj = PyPtr.new(pyobj) if pyobj.kind_of? FFI::Pointer
      pyobj = pyobj.__pyobj__ unless pyobj.kind_of? PyPtr

      pytype = PyPtr.new(pytype) if pytype.kind_of? FFI::Pointer
      pytype = ptype.__pyobj__ unless pytype.kind_of? PyPtr

      LibPython.PyObject_IsInstance(pyobj, pytype) == 1
    end

    class << self
      private def check_pyobject(pyobj)
        # TODO: Check whether pyobj is PyObject
      end
    end
  end

  class PyPtr
    def kind_of?(other)
      case other
      when self.class
        Types.pyisinstance(self, other)
      else
        super
      end
    end
  end
end
