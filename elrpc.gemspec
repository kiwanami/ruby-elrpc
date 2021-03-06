# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'elrpc/version'

Gem::Specification.new do |spec|
  spec.name          = "elrpc"
  spec.version       = Elrpc::VERSION
  spec.authors       = ["SAKURAI Masashi"]
  spec.email         = ["m.sakurai@kiwanami.net"]
  spec.summary       = %q{EPC (RPC stack for the Emacs Lisp) for Ruby.}
  spec.description   = %q{EPC (RPC stack for the Emacs Lisp) for Ruby.}
  spec.homepage      = "https://github.com/kiwanami/ruby-elrpc"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "elparser", "~> 0.0"
  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", ">= 12.3.3"
  spec.add_development_dependency "test-unit", "~> 3"
end
