require "simplecov"
SimpleCov.start do
  add_filter "/test/"
  add_filter "/vendor/"
  enable_coverage :branch
end

$LOAD_PATH.unshift(File.dirname(__FILE__) + "/../lib")

require "test/unit"
require "simple-rss"
