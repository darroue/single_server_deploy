Gem::Specification.new do |s|
  s.required_ruby_version = '3.3.0'
  s.name = 'single_server_deploy'
  s.version = '0.2.2'
  s.summary = 'Single Server Deploy'
  s.description = 'This GEM allows you to build and deploy your application to preferred server based on few required ENVs'
  s.authors = ['Petr Radouš']
  s.email = 'darroue@gmail.com'
  s.homepage = 'https://petr-radous.cz'
  s.license = 'MIT'
  s.files = Dir['{bin,lib}/**/*', 'README.md']
  s.require_paths = ['lib']
  s.executables = Dir['bin/*'].map { |f| File.basename(f) }
end
