require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake/extensiontask"

Rake::ExtensionTask.new('pycall_ext')
RSpec::Core::RakeTask.new(:spec)

task :default => :spec
