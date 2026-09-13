require "simple-rss"
require "optparse"

options = {}
arguments = OptionParser.new do |parser|
  parser.banner = "Usage: ruby -Ilib examples/digest.rb [--source-url URL] FEED_FILE..."
  parser.on("--source-url URL", "Base URL for relative feed references") { |url| options[:source_url] = url }
end
arguments.parse!
abort arguments.to_s if ARGV.empty?

entries = ARGV.flat_map do |path|
  File.open(path) { |source| SimpleRSS.parse(source, options).normalized_entries }
end

entries.sort_by { |entry| entry.effective_at ? -entry.effective_at.to_r : Float::INFINITY }.each do |entry|
  puts [entry.title || entry.identifier || "Untitled", entry.effective_at&.getutc&.iso8601, entry.url, entry.content_text].compact.join("\n")
  puts
end
