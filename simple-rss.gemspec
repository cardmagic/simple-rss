Gem::Specification.new do |s|
  s.name = "simple-rss"
  s.version = "1.3.3"
  s.version = "#{s.version}-alpha-#{ENV['TRAVIS_BUILD_NUMBER']}" if ENV["TRAVIS"]
  s.date = "2015-08-17"
  s.summary = "A simple, flexible, extensible, and liberal RSS and Atom reader for Ruby. It is designed to be backwards compatible with the standard RSS parser, but will never do RSS generation."
  s.email = "lucas@rufy.com"
  s.homepage = "http://github.com/cardmagic/simple-rss"
  s.description = "A simple, flexible, extensible, and liberal RSS and Atom reader for Ruby. It is designed to be backwards compatible with the standard RSS parser, but will never do RSS generation."
  s.authors = ["Lucas Carlson"]
  s.files = Dir["lib/**/*", "test/**/*", "LICENSE", "README.markdown", "Rakefile", "simple-rss.gemspec"]
  s.rubyforge_project = "simple-rss"
  s.add_development_dependency "rake"
  s.add_development_dependency "rdoc"
  s.add_development_dependency "test-unit"
end
