
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "mysql_simple_orm/version"

Gem::Specification.new do |spec|
  spec.name          = "mysql_simple_orm"
  spec.version       = MysqlSimpleOrm::VERSION
  spec.authors       = ["Melvin Rodriguez"]
  spec.email         = ["melvinrr25@gmail.com"]

  spec.summary       = %q{Simple Mysql2 ORM to handle models}
  spec.description   = %q{Simple Mysql2 ORM}
  spec.homepage      = "https://github.com/melvinrr25/mysql_simple_orm"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
