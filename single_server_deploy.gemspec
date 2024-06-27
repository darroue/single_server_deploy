Gem::Specification.new do |s|
  s.required_ruby_version = '>= 3.3.3'
  s.name = 'single_server_deploy'
  s.version = '0.3.4'
  s.summary = 'Single Server Deploy'
  s.description = 'This GEM allows you to build and deploy your application to preferred server based on few required ENVs'
  s.authors = ['Petr Radouš']
  s.email = 'darroue@gmail.com'
  s.homepage = 'https://petr-radous.cz'
  s.license = 'MIT'
  s.files = Dir['{bin,lib}/**/*', 'README.md']
  s.require_paths = ['lib']
  s.executables = Dir['bin/*'].map { |f| File.basename(f) }

  s.add_runtime_dependency 'dotenv', '~> 3.1'
  s.add_runtime_dependency 'securerandom', '~> 0.3.1'
  s.add_runtime_dependency 'yaml', '~> 0.3.0'

  s.add_development_dependency 'rubocop', '~> 1.63.4'
  s.add_development_dependency 'ruby-lsp', '~> 0.16.6'
end
