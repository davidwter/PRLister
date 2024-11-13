# pr_lister.gemspec
require 'rubygems'

Gem::Specification.new do |s|
  s.name        = 'pr_lister'
  s.version     = '1.0.0'
  s.summary     = 'List GitHub Pull Requests'
  s.description = 'A tool to list and analyze GitHub Pull Requests'
  s.authors     = ['Your Name']
  s.email       = 'your@email.com'
  s.homepage    = 'https://github.com/yourusername/pr_lister'
  s.required_ruby_version = '>= 2.7.0'

  s.files = [
    'lib/pr_lister.rb',
    'bin/pr_lister'
  ]
  s.bindir = 'bin'
  s.executables = ['pr_lister']
  s.require_paths = ['lib']
  s.license = 'MIT'

  s.add_runtime_dependency 'octokit', '~> 5.0'
  s.add_runtime_dependency 'rubygems-update', '~> 3.4'

  s.metadata = {
    "source_code_uri" => "https://github.com/yourusername/pr_lister"
  }
end