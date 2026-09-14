# rbs_inline: enabled

require_relative "http_client"

class SimpleRSS::Discovery
  MEDIA_TYPES = {
    "application/rss+xml" => :rss, "application/rdf+xml" => :rss,
    "application/atom+xml" => :atom, "application/feed+json" => :json_feed, "application/json" => :json_feed
  }.freeze

  # @rbs @options: Hash[Symbol, untyped]
  # @rbs @parser: untyped

  # @rbs (Hash[Symbol, untyped]) -> void
  def initialize(options)
    @options = { network_policy: :public }.merge(options)
    require "nokogiri"
    @parser = Object.const_get(:Nokogiri)
    unless @parser.const_defined?(:HTML5)
      raise SimpleRSS::DiscoveryDependencyError, "Discovery requires Nokogiri HTML5 support (available on CRuby)"
    end
  rescue LoadError
    raise SimpleRSS::DiscoveryDependencyError, 'Install the optional "nokogiri" gem (>= 1.16, < 2) to use SimpleRSS.discover'
  end

  # @rbs (String) -> Array[Hash[Symbol, untyped]]
  def discover(url)
    raise SimpleRSS::PolicyError, "Expected a website URL string" unless url.is_a?(String)

    url = "https:#{url}" if url.start_with?("//")
    url = "https://#{url}" unless url.match?(/\A[a-z][a-z\d+.-]*:/i)
    response, uri = SimpleRSS::HTTPClient.new(@options).get(url)
    raise SimpleRSS::HTTPError, response.code.to_i unless response.is_a?(Net::HTTPSuccess)

    candidates(response.body.to_s, uri, response.content_type, response.type_params["charset"])
  end

  private

  # @rbs (String, untyped, String?, String?) -> Array[Hash[Symbol, untyped]]
  def candidates(body, uri, media_type, encoding)
    prefix = body.b.sub(/\A\xEF\xBB\xBF/n, "").lstrip
    return [feed_candidate(body, uri, :json_feed)] if prefix.start_with?("{", "[")

    document = @parser::XML.parse(body, uri.to_s, nil, @parser::XML::ParseOptions::NONET | @parser::XML::ParseOptions::RECOVER)
    root = document.root
    format = root && xml_format(root)
    return [feed_candidate(body, uri, format)] if format

    unless root&.name&.casecmp?("html") || %w[text/html application/xhtml+xml].include?(media_type) || prefix.match?(/\A(?:<!doctype\s+html|<html\b|<head\b)/i)
      raise SimpleRSS::DiscoveryError, "Response is not a recognized feed or HTML page"
    end

    html_candidates(body, uri, encoding)
  rescue SimpleRSS::RequestError, SimpleRSS::DiscoveryError
    raise
  rescue SimpleRSSError, ArgumentError, EncodingError => e
    raise SimpleRSS::DiscoveryError, "Cannot parse discovery response: #{e.message}"
  end

  # @rbs (untyped) -> Symbol?
  def xml_format(root)
    return :rss if root.name == "rss" && root.namespace.nil?
    return :atom if root.name == "feed" && [SimpleRSS::ATOM_NAMESPACE, "http://purl.org/atom/ns#"].include?(root.namespace&.href)
    return :rss if root.name == "RDF" && root.namespace&.href == "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

    nil
  end

  # @rbs (String, untyped, Symbol) -> Hash[Symbol, untyped]
  def feed_candidate(body, uri, format)
    feed = SimpleRSS.parse(body, source_url: uri.to_s)
    title = feed.instance_variable_get(:@title)
    { url: uri.to_s, title: title, format: format, media_type: MEDIA_TYPES.key(format), source: :document, verified: true }
  end

  # @rbs (String, untyped, String?) -> Array[Hash[Symbol, untyped]]
  def html_candidates(body, uri, encoding)
    document = @parser::HTML5.parse(body, uri.to_s, encoding, max_tree_depth: 128, max_attributes: 128)
    head = document.at_css("html > head")
    return [] unless head

    base = resolve_url(head.at_xpath("./base[@href]")&.[]("href"), uri) || uri
    candidates = head.xpath("./link[@rel][@type][@href]").filter_map do |link|
      next unless link["rel"].downcase.split.include?("alternate")

      media_type = link["type"].split(";", 2).first.to_s.strip.downcase
      format = MEDIA_TYPES[media_type]
      next unless format

      target = resolve_url(link["href"], base)
      next unless target

      { url: target.to_s, title: link["title"], format: format, media_type: media_type, source: :html_link, verified: false }
    end
    candidates.uniq { |candidate| candidate[:url] }
  end

  # @rbs (String?, untyped) -> untyped
  def resolve_url(value, base)
    return if value.nil? || value.strip.empty?

    SimpleRSS::RequestPolicy.parse_url(URI.join(base.to_s, value.strip).to_s)
  rescue URI::Error, SimpleRSS::PolicyError
    nil
  end
end
