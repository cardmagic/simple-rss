require 'lib/simple-rss'

Gem::Specification.new do |s|
  s.name = "simple-rss"
  s.version = "#{SimpleRSS::VERSION}-cardmagic"
  s.date = "2008-07-15"
  s.summary = "A simple, flexible, extensible, and liberal RSS and Atom reader for Ruby. It is designed to be backwards compatible with the standard RSS parser, but will never do RSS generation."
  s.email = "lucas@rufy.com"
  s.homepage = "http://github.com/cardmagic/simple-rss"
  s.description = "A simple, flexible, extensible, and liberal RSS and Atom reader for Ruby. It is designed to be backwards compatible with the standard RSS parser, but will never do RSS generation."
  s.has_rdoc = true
  s.authors = ["Lucas Carlson"]
  s.files = Dir["**/*"]
end
