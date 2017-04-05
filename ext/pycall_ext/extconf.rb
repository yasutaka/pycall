require 'mkmf'

if with_config('pyptr_init_log', false)
  $defs.push "-DPYCALL_PYPTR_INIT_LOG" unless $defs.include? "-DPYCALL_PYPTR_INIT_LOG"
end

create_makefile('pycall_ext')
