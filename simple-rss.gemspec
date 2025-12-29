Gem::Specification.new do |s|
  s.name = "simple-rss"
  s.version = "2.1.0"
  s.date = "2025-12-29"
  s.summary = "A simple, flexible, extensible, and liberal RSS and Atom reader for Ruby. It is designed to be backwards compatible with the standard RSS parser, but will never do RSS generation."
  s.email = "lucas@rufy.com"
  s.homepage = "https://github.com/cardmagic/simple-rss"
  s.description = "A simple, flexible, extensible, and liberal RSS and Atom reader for Ruby. It is designed to be backwards compatible with the standard RSS parser, but will never do RSS generation."
  s.authors = ["Lucas Carlson"]
  s.files = Dir["lib/**/*", "test/**/*", "LICENSE", "README.md", "Rakefile", "simple-rss.gemspec"]
  s.required_ruby_version = ">= 3.1"
  s.add_development_dependency "rake"
  s.add_development_dependency "rdoc"
  s.add_development_dependency "test-unit"
end
