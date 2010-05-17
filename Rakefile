require 'rake'

desc "Run all specs"
task 'spec' do
  exec "appcfg.rb", "run", "bin/spec", *FileList['spec/**/*_spec.rb'].join(' ')
end