require "simple-rss"
require "feedbag"

abort "Usage: ruby -Ilib examples/feedbag.rb WEBSITE_URL" unless ARGV.size == 1

Feedbag.find(ARGV.first, open_timeout: 10, read_timeout: 10).each do |url|
  puts url
  feed = SimpleRSS.fetch(url, network_policy: :public, timeout: 10)
  feed&.normalized_entries&.each { |entry| puts entry.title || entry.identifier }
end
