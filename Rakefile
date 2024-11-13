# Rakefile
require 'bundler/gem_tasks'
require 'rake'
require 'rake/clean'

CLEAN.include('*.gem')
CLOBBER.include('pkg')

task :default => :build

desc "Build gem"
task :build do
  sh "gem build pr_lister.gemspec"
end

desc "Install gem locally"
task :install => :build do
  sh "gem install pr_lister-1.0.0.gem --local"
end

desc "Clean and rebuild"
task :rebuild => [:clean, :build]