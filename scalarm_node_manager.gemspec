# -*- encoding: utf-8 -*-
require File.expand_path('../lib/scalarm_node_manager/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Dariusz Król"]
  gem.email         = ["dkrol@agh.edu.pl"]
  gem.description   = %q{Write a gem description}
  gem.summary       = %q{Scalarm Node Manager manages and monitors a single physical or virtual host.}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "scalarm_node_manager"
  gem.require_paths = ["lib"]
  gem.version       = ScalarmNodeManager::VERSION
  # dependencies
  gem.add_dependency("sinatra", "1.3.2")
  gem.add_dependency("daemons", "1.1.8")
  gem.add_dependency("mongo", "1.6.4")
end
