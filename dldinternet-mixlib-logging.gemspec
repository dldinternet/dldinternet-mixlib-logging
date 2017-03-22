# -*- encoding: utf-8 -*-

require File.expand_path('../lib/dldinternet/mixlib/logging/version', __FILE__)

Gem::Specification.new do |gem|
  gem.name          = "dldinternet-mixlib-logging"
  gem.version       = Dldinternet::Mixlib::Logging::VERSION
  gem.summary       = %q{A logging mixlib}
  gem.description   = %q{A logging mixlib to help CLI apps which repeat the same logging patterns}
  gem.license       = "Apachev2"
  gem.authors       = ["Christo De Lange"]
  gem.email         = "rubygems@dldinternet.com"
  gem.homepage      = "https://rubygems.org/gems/dldinternet-mixlib-logging"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ['lib']

  gem.add_dependency 'logging', '~> 2.1', '>= 2.1.0'

  gem.add_development_dependency 'bundler', '~> 1.2'
  gem.add_development_dependency 'rake', '~> 10.0'
  gem.add_development_dependency 'rubygems-tasks', '~> 0.2'
  gem.add_development_dependency 'cucumber', '~> 0.10', '>= 0.10.2'
end
