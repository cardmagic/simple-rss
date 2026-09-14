Gem::Specification.new do |s|
  s.name = "simple-rss"
  s.version = "2.3.0"
  s.summary = "A flexible RSS, Atom, and JSON Feed reader for Ruby."
  s.email = "lucas@rufy.com"
  s.homepage = "https://github.com/cardmagic/simple-rss"
  s.metadata["changelog_uri"] = "https://github.com/cardmagic/simple-rss/blob/master/CHANGELOG.md"
  s.description = "Parse RSS, Atom, and JSON Feed with normalized entries, HTTP fetching, website feed discovery, and JSON/XML serialization."
  s.authors = ["Lucas Carlson"]
  s.files = Dir["lib/**/*", "examples/**/*", "test/**/*", "LICENSE", "README.md", "CHANGELOG.md", "Rakefile", "simple-rss.gemspec"]
  s.required_ruby_version = ">= 3.1"
  s.add_development_dependency "rake"
  s.add_development_dependency "rdoc"
  s.add_development_dependency "test-unit"
end
