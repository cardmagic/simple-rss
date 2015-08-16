Gem::Specification.new do |s|
  s.name = "simple-rss"
  s.version = "1.2.3"
  s.version = "#{s.version}-alpha-#{ENV['TRAVIS_BUILD_NUMBER']}" if ENV['TRAVIS']
  s.date = "2010-07-06"
  s.summary = "A simple, flexible, extensible, and liberal RSS and Atom reader for Ruby. It is designed to be backwards compatible with the standard RSS parser, but will never do RSS generation."
  s.email = "lucas@rufy.com"
  s.homepage = "http://github.com/cardmagic/simple-rss"
  s.description = "A simple, flexible, extensible, and liberal RSS and Atom reader for Ruby. It is designed to be backwards compatible with the standard RSS parser, but will never do RSS generation."
  s.has_rdoc = true
  s.authors = ["Lucas Carlson"]
  s.files = ["install.rb", "lib", "lib/simple-rss.rb", "LICENSE", "Rakefile", "README.markdown", "simple-rss.gemspec", "test", "test/base", "test/base/base_test.rb", "test/data", "test/data/atom.xml", "test/data/not-rss.xml", "test/data/rss09.rdf", "test/data/rss20.xml", "test/test_helper.rb"]
  s.rubyforge_project = 'simple-rss'
  s.add_development_dependency "rake"
  s.add_development_dependency "rdoc"
  s.add_development_dependency "test-unit"
end
