require 'spec_helper'

RSpec.describe PyCall do
  describe '.wrap_ruby_object' do
    it 'registers the wrapped ruby object into GCGuard table' do
      obj = Object.new
      wrapped = PyCall.wrap_ruby_object(obj)
      expect(PyCall.const_get(:GCGuard).guarded_object_count).to eq(1)

      obj_id, obj = obj.object_id, nil
      GC.start
      expect{ ObjectSpace._id2ref(obj_id) }.not_to raise_error

      PyCall::LibPython.Py_DecRef(wrapped)
      wrapped = nil
      expect(PyCall.const_get(:GCGuard).guarded_object_count).to eq(0)
      GC.start
      expect{ ObjectSpace._id2ref(obj_id) }.to raise_error(RangeError)
    end
  end

  describe '.wrap_ruby_callable' do
    specify do
      expect { |b|
        PyCall.eval(<<PYTHON, input_type: :file)
def call_function(f, x):
  return f(str(x))
PYTHON
        begin
          f = PyCall.wrap_ruby_callable(b.to_proc)
          PyCall.eval('call_function').(f, 42)
        ensure
          PyCall::LibPython.Py_DecRef(f)
          f = nil
        end
      }.to yield_with_args('42')
    end
  end
end
