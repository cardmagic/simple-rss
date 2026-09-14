require "simple-rss"

abort "Usage: ruby -Ilib examples/discover.rb WEBSITE_URL" unless ARGV.size == 1

candidates = SimpleRSS.discover(ARGV.first)
if candidates.empty?
  puts "No advertised feeds found."
  exit
end

candidates.each do |candidate|
  verification = candidate[:verified] ? "parsed feed" : "advertised link"
  puts [candidate[:title], candidate[:format], candidate[:url], verification].compact.join(" | ")
end
