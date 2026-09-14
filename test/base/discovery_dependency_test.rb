require "test_helper"
require "open3"

class DiscoveryDependencyTest < Test::Unit::TestCase
  def test_core_parsing_works_without_loading_nokogiri_and_discovery_explains_the_dependency
    script = <<~RUBY_SCRIPT
      require "simple-rss"
      abort "Nokogiri loaded by core" if defined?(Nokogiri)
      Kernel.prepend(Module.new do
        def require(path)
          raise LoadError, "optional dependency is unavailable" if path == "nokogiri"

          super
        end
      end)
      feed = SimpleRSS.parse('<rss version="2.0"><channel><title>Example</title></channel></rss>')
      abort "Core parsing failed" unless feed.title == "Example"
      begin
        SimpleRSS.discover("http://127.0.0.1/", timeout: 0.1)
        abort "Expected a dependency error"
      rescue SimpleRSS::DiscoveryDependencyError => error
        puts error.message
      end
    RUBY_SCRIPT
    output, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", script)
    assert status.success?, output
    assert_include output, 'Install the optional "nokogiri" gem'
  end
end
