Gem::Specification.new do |s|
  s.name          = 'logstash-mixin-port_management_support'
  s.version       = '1.0.0'
  s.licenses      = %w(Apache-2.0)
  s.summary       = "Support for port management in Logstash plugins, independent of Logstash version"
  s.description   = "This gem is meant to be a dependency of any Logstash plugin that wishes to manage TCP ports"
  s.authors       = %w(Elastic)
  s.email         = 'info@elastic.co'
  s.homepage      = 'https://github.com/logstash-plugins/logstash-mixin-port_management_support'
  s.require_paths = %w(lib)

  s.files = %w(lib spec vendor).flat_map{|dir| Dir.glob("#{dir}/**/*")}+Dir.glob(["*.md","LICENSE"])

  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  s.platform = RUBY_PLATFORM

  s.add_runtime_dependency 'logstash-core', '>= 7.0.0'

  s.add_development_dependency 'logstash-devutils'
  s.add_development_dependency 'rspec', '~> 3.9'
end
