# rbs_inline: enabled

require "cgi"
require "time"

class SimpleRSS
  # @rbs skip
  include Enumerable

  # @rbs!
  #   include Enumerable[Hash[Symbol, untyped]]

  VERSION = "2.0.0".freeze

  # @rbs @items: Array[Hash[Symbol, untyped]]
  # @rbs @source: String
  # @rbs @options: Hash[Symbol, untyped]
  # @rbs @etag: String?
  # @rbs @last_modified: String?

  attr_reader :items #: Array[Hash[Symbol, untyped]]
  attr_reader :source #: String
  attr_reader :etag #: String?
  attr_reader :last_modified #: String?
  alias entries items #: Array[Hash[Symbol, untyped]]

  @@feed_tags = %i[
    id
    title subtitle link
    description
    author webMaster managingEditor contributor
    pubDate lastBuildDate updated dc:date
    generator language docs cloud
    ttl skipHours skipDays
    image logo icon rating
    rights copyright
    textInput feedburner:browserFriendly
    itunes:author itunes:category
  ]

  @@item_tags = %i[
    id
    title link link+alternate link+self link+edit link+replies
    author contributor
    description summary content content:encoded comments
    pubDate published updated expirationDate modified dc:date
    category guid
    trackback:ping trackback:about
    dc:creator dc:title dc:subject dc:rights dc:publisher
    feedburner:origLink
    media:content#url media:content#type media:content#height media:content#width media:content#duration
    media:title media:thumbnail#url media:thumbnail#height media:thumbnail#width
    media:credit media:credit#role
    media:category media:category#scheme
  ]

  # @rbs (untyped, ?Hash[Symbol, untyped]) -> void
  def initialize(source, options = {})
    @source = source.respond_to?(:read) ? source.read.to_s : source.to_s
    @items = [] #: Array[Hash[Symbol, untyped]]
    @options = {} #: Hash[Symbol, untyped]
    @options.update(options)

    parse
  end

  # @rbs () -> SimpleRSS
  def channel
    self
  end
  alias feed channel

  # Iterate over all items in the feed
  #
  # @rbs () { (Hash[Symbol, untyped]) -> void } -> self
  #    | () -> Enumerator[Hash[Symbol, untyped], self]
  def each(&block)
    return enum_for(:each) unless block

    items.each(&block)
    self
  end

  # Access an item by index
  #
  # @rbs (Integer) -> Hash[Symbol, untyped]?
  def [](index)
    items[index]
  end

  # Get the n most recent items, sorted by date
  #
  # @rbs (?Integer) -> Array[Hash[Symbol, untyped]]
  def latest(count = 10)
    items.sort_by { |item| item[:pubDate] || item[:updated] || Time.at(0) }.reverse.first(count)
  end

  # @rbs (?Hash[Symbol, untyped]) -> Hash[Symbol, untyped]
  def as_json(_options = {})
    hash = {} #: Hash[Symbol, untyped]

    @@feed_tags.each do |tag|
      tag_cleaned = clean_tag(tag)
      value = instance_variable_get("@#{tag_cleaned}")
      hash[tag_cleaned] = serialize_value(value) if value
    end

    hash[:items] = items.map do |item|
      item.transform_values { |v| serialize_value(v) }
    end

    hash
  end

  # @rbs (*untyped) -> String
  def to_json(*)
    require "json"
    JSON.generate(as_json)
  end

  alias to_hash as_json

  # @rbs (?format: Symbol) -> String
  def to_xml(format: :rss2)
    case format
    when :rss2 then to_rss2_xml
    when :atom then to_atom_xml
    else raise ArgumentError, "Unknown format: #{format}. Supported: :rss2, :atom"
    end
  end

  class << self
    # @rbs () -> Array[Symbol]
    def feed_tags
      @@feed_tags
    end

    # @rbs (Array[Symbol]) -> Array[Symbol]
    def feed_tags=(ft)
      @@feed_tags = ft
    end

    # @rbs () -> Array[Symbol]
    def item_tags
      @@item_tags
    end

    # @rbs (Array[Symbol]) -> Array[Symbol]
    def item_tags=(it)
      @@item_tags = it
    end

    # The strict attribute is for compatibility with Ruby's standard RSS parser
    #
    # @rbs (untyped, ?Hash[Symbol, untyped]) -> SimpleRSS
    def parse(source, options = {})
      new source, options
    end

    # Fetch and parse a feed from a URL
    # Returns nil if conditional GET returns 304 Not Modified
    #
    # @rbs (String, ?Hash[Symbol, untyped]) -> SimpleRSS?
    def fetch(url, options = {})
      require "net/http"
      require "uri"

      uri = URI.parse(url)
      response = perform_fetch(uri, options)

      return nil if response.is_a?(Net::HTTPNotModified)

      raise SimpleRSSError, "HTTP #{response.code}: #{response.message}" unless response.is_a?(Net::HTTPSuccess)

      body = response.body.force_encoding(Encoding::UTF_8)
      feed = parse(body, options)
      feed.instance_variable_set(:@etag, response["ETag"])
      feed.instance_variable_set(:@last_modified, response["Last-Modified"])
      feed
    end

    private

    # @rbs (untyped, Hash[Symbol, untyped]) -> untyped
    def perform_fetch(uri, options)
      http = build_http(uri, options)
      request = build_request(uri, options)

      response = http.request(request)
      handle_redirect(response, options) || response
    end

    # @rbs (untyped, Hash[Symbol, untyped]) -> untyped
    def build_http(uri, options)
      host = uri.host || raise(SimpleRSSError, "Invalid URL: missing host")
      http = Net::HTTP.new(host, uri.port)
      http.use_ssl = uri.scheme == "https"

      timeout = options[:timeout]
      if timeout
        http.open_timeout = timeout
        http.read_timeout = timeout
      end

      http
    end

    # @rbs (untyped, Hash[Symbol, untyped]) -> untyped
    def build_request(uri, options)
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "SimpleRSS/#{VERSION}"

      # Conditional GET headers
      request["If-None-Match"] = options[:etag] if options[:etag]
      request["If-Modified-Since"] = options[:last_modified] if options[:last_modified]

      # Custom headers
      options[:headers]&.each { |key, value| request[key] = value }

      request
    end

    # @rbs (untyped, Hash[Symbol, untyped]) -> untyped
    def handle_redirect(response, options)
      return nil unless response.is_a?(Net::HTTPRedirection)
      return nil if options[:follow_redirects] == false

      location = response["Location"]
      return nil unless location

      redirects = (options[:_redirects] || 0) + 1
      raise SimpleRSSError, "Too many redirects" if redirects > 5

      new_options = options.merge(_redirects: redirects)
      perform_fetch(URI.parse(location), new_options)
    end
  end

  DATE_TAGS = %i[pubDate lastBuildDate published updated expirationDate modified dc:date].freeze
  STRIP_HTML_TAGS = %i[author contributor skipHours skipDays].freeze

  private

  # @rbs () -> void
  def parse
    raise SimpleRSSError, "Poorly formatted feed" unless @source =~ %r{<(channel|feed).*?>.*?</(channel|feed)>}mi

    # Feed's title and link
    feed_content = Regexp.last_match(1) if @source =~ %r{(.*?)<(rss:|atom:)?(item|entry).*?>.*?</(rss:|atom:)?(item|entry)>}mi

    # Capture channel/feed tag attributes
    feed_attrs = nil
    if @source =~ /<(channel|feed)([\s][^>]*)?>/mi
      feed_attrs = Regexp.last_match(2)
    end

    @@feed_tags.each do |tag|
      next if tag.to_s.strip.empty?

      tag_str = tag.to_s

      # Handle channel#attr or feed#attr syntax
      if tag_str.include?("#")
        parse_feed_attr_tag(tag_str, feed_attrs)
        next
      end

      if feed_content && feed_content =~ %r{<(rss:|atom:)?#{tag}(.*?)>(.*?)</(rss:|atom:)?#{tag}>}mi
        nil
      elsif feed_content && feed_content =~ %r{<(rss:|atom:)?#{tag}(.*?)\/\s*>}mi
        nil
      elsif @source =~ %r{<(rss:|atom:)?#{tag}(.*?)>(.*?)</(rss:|atom:)?#{tag}>}mi
        nil
      elsif @source =~ %r{<(rss:|atom:)?#{tag}(.*?)\/\s*>}mi
        nil
      end

      next unless Regexp.last_match(2) || Regexp.last_match(3)

      tag_cleaned = clean_tag(tag)
      instance_variable_set("@#{tag_cleaned}", clean_content(tag, Regexp.last_match(2), Regexp.last_match(3)))
      self.class.class_eval("attr_reader :#{tag_cleaned}")
    end

    # RSS items' title, link, and description
    @source.scan(%r{<(rss:|atom:)?(item|entry)([\s][^>]*)?>(.*?)</(rss:|atom:)?(item|entry)>}mi) do |match|
      item = {} #: Hash[Symbol, untyped]
      @@item_tags.each do |tag|
        next if tag.to_s.strip.empty?

        parse_item_tag(item, tag, match[3], match[2])
      end
      item.define_singleton_method(:method_missing) { |name, *| self[name] }
      @items << item
    end
  end

  # @rbs (Hash[Symbol, untyped], Symbol, String?, String?) -> void
  def parse_item_tag(item, tag, content, item_attrs = nil)
    return if content.nil?

    tag_str = tag.to_s

    return parse_rel_tag(item, tag_str, content) if tag_str.include?("+")
    return parse_attr_tag(item, tag_str, content, item_attrs) if tag_str.include?("#")

    parse_simple_tag(item, tag, content)
  end

  # @rbs (Hash[Symbol, untyped], String, String) -> void
  def parse_rel_tag(item, tag_str, content)
    tag, rel = tag_str.split("+")
    return unless tag && rel

    content =~ %r{<(rss:|atom:)?#{tag}(.*?)rel=['"]#{rel}['"](.*?)>(.*?)</(rss:|atom:)?#{tag}>}mi ||
      content =~ %r{<(rss:|atom:)?#{tag}(.*?)rel=['"]#{rel}['"](.*?)/\s*>}mi

    return unless Regexp.last_match(3) || Regexp.last_match(4)

    item[clean_tag("#{tag}+#{rel}")] = clean_content(tag.to_sym, Regexp.last_match(3), Regexp.last_match(4))
  end

  # @rbs (String, String?) -> void
  def parse_feed_attr_tag(tag_str, feed_attrs)
    tag, attrib = tag_str.split("#")
    return unless tag && attrib && feed_attrs

    # Only handle channel or feed tags
    return unless %w[channel feed].include?(tag)
    return unless feed_attrs =~ /#{attrib}=['"](.*?)['"]/mi

    tag_cleaned = clean_tag("#{tag}_#{attrib}")
    instance_variable_set("@#{tag_cleaned}", clean_content(tag.to_sym, attrib, Regexp.last_match(1)))
    self.class.class_eval("attr_reader :#{tag_cleaned}")
  end

  # @rbs (Hash[Symbol, untyped], String, String, String?) -> void
  def parse_attr_tag(item, tag_str, content, item_attrs = nil)
    tag, attrib = tag_str.split("#")
    return unless tag && attrib

    # Handle attributes on the item/entry tag itself
    if %w[item entry].include?(tag) && item_attrs
      return unless item_attrs =~ /#{attrib}=['"](.*?)['"]/mi

      item[clean_tag("#{tag}_#{attrib}")] = clean_content(tag.to_sym, attrib, Regexp.last_match(1))
      return
    end

    content =~ %r{<(rss:|atom:)?#{tag}(.*?)#{attrib}=['"](.*?)['"](.*?)>(.*?)</(rss:|atom:)?#{tag}>}mi ||
      content =~ %r{<(rss:|atom:)?#{tag}(.*?)#{attrib}=['"](.*?)['"](.*?)/\s*>}mi

    return unless Regexp.last_match(3)

    item[clean_tag("#{tag}_#{attrib}")] = clean_content(tag.to_sym, attrib, Regexp.last_match(3))
  end

  # @rbs (Hash[Symbol, untyped], Symbol, String) -> void
  def parse_simple_tag(item, tag, content)
    # Handle array_tags option - collect all values for this tag
    if array_tag?(tag)
      values = content.scan(%r{<(rss:|atom:)?#{tag}(?:[^>]*)>(.*?)</(rss:|atom:)?#{tag}>}mi).map do |match|
        clean_content(tag, nil, match[1])
      end
      item[clean_tag(tag)] = values unless values.empty?
      return
    end

    content =~ %r{<(rss:|atom:)?#{tag}(.*?)>(.*?)</(rss:|atom:)?#{tag}>}mi ||
      content =~ %r{<(rss:|atom:)?#{tag}(.*?)/\s*>}mi

    return unless Regexp.last_match(2) || Regexp.last_match(3)

    item[clean_tag(tag)] = clean_content(tag, Regexp.last_match(2), Regexp.last_match(3))
  end

  # @rbs (Symbol) -> bool
  def array_tag?(tag)
    array_tags = @options[:array_tags]
    return false unless array_tags.is_a?(Array)

    array_tags.include?(tag) || array_tags.include?(tag.to_sym)
  end

  # @rbs (Symbol, String?, String?) -> (Time | String)
  def clean_content(tag, attrs, content)
    content = content.to_s

    return parse_date(content) if DATE_TAGS.include?(tag)
    return unescape(content.gsub(/<.*?>/, "")) if STRIP_HTML_TAGS.include?(tag)
    return extract_href(attrs) if content.empty? && attrs

    unescape(content)
  end

  # @rbs (String) -> (Time | String)
  def parse_date(content)
    Time.parse(content)
  rescue StandardError
    unescape(content)
  end

  # @rbs (String?) -> String
  def extract_href(attrs)
    return "" unless "#{attrs} " =~ /href=['"]?([^'"]*)['" ]/mi

    Regexp.last_match(1)&.strip || ""
  end

  # @rbs (Symbol | String) -> Symbol
  def clean_tag(tag)
    tag.to_s.tr(":", "_").intern
  end

  # @rbs (untyped) -> untyped
  def serialize_value(value)
    case value
    when Time then value.iso8601
    else value
    end
  end

  # @rbs (String?) -> String
  def escape_xml(text)
    return "" if text.nil?

    text.to_s
        .gsub("&", "&amp;")
        .gsub("<", "&lt;")
        .gsub(">", "&gt;")
        .gsub("'", "&apos;")
        .gsub('"', "&quot;")
  end

  # @rbs (Array[String], String, untyped) -> void
  def add_xml_element(elements, tag, value)
    elements << "<#{tag}>#{escape_xml(value)}</#{tag}>" if value
  end

  # @rbs (Array[String], String, untyped, Symbol) -> void
  def add_xml_time_element(elements, tag, value, format)
    return unless value.is_a?(Time)

    formatted = format == :rfc2822 ? value.rfc2822 : value.iso8601
    elements << "<#{tag}>#{formatted}</#{tag}>"
  end

  # @rbs () -> String
  def to_rss2_xml
    xml = ['<?xml version="1.0" encoding="UTF-8"?>', '<rss version="2.0">', "<channel>"]
    xml.concat(rss2_channel_elements)
    items.each { |item| xml.concat(rss2_item_elements(item)) }
    xml << "</channel>"
    xml << "</rss>"
    xml.join("\n")
  end

  # @rbs () -> Array[String]
  def rss2_channel_elements
    elements = [] #: Array[String]
    add_xml_element(elements, "title", instance_variable_get(:@title))
    add_xml_element(elements, "link", instance_variable_get(:@link))
    add_xml_element(elements, "description", instance_variable_get(:@description))
    add_xml_element(elements, "language", instance_variable_get(:@language))
    add_xml_time_element(elements, "pubDate", instance_variable_get(:@pubDate), :rfc2822)
    add_xml_time_element(elements, "lastBuildDate", instance_variable_get(:@lastBuildDate), :rfc2822)
    add_xml_element(elements, "generator", instance_variable_get(:@generator))
    elements
  end

  # @rbs (Hash[Symbol, untyped]) -> Array[String]
  def rss2_item_elements(item)
    elements = ["<item>"] #: Array[String]
    elements << "<title>#{escape_xml(item[:title])}</title>" if item[:title]
    elements << "<link>#{escape_xml(item[:link])}</link>" if item[:link]
    elements << "<description><![CDATA[#{item[:description]}]]></description>" if item[:description]
    elements << "<pubDate>#{item[:pubDate].rfc2822}</pubDate>" if item[:pubDate].is_a?(Time)
    elements << "<guid>#{escape_xml(item[:guid])}</guid>" if item[:guid]
    elements << "<author>#{escape_xml(item[:author])}</author>" if item[:author]
    elements << "<category>#{escape_xml(item[:category])}</category>" if item[:category]
    elements << "</item>"
    elements
  end

  # @rbs () -> String
  def to_atom_xml
    xml = ['<?xml version="1.0" encoding="UTF-8"?>', '<feed xmlns="http://www.w3.org/2005/Atom">']
    xml.concat(atom_feed_elements)
    items.each { |item| xml.concat(atom_entry_elements(item)) }
    xml << "</feed>"
    xml.join("\n")
  end

  # @rbs () -> Array[String]
  def atom_feed_elements
    elements = [] #: Array[String]
    title_val = instance_variable_get(:@title)
    link_val = instance_variable_get(:@link)
    id_val = instance_variable_get(:@id)
    add_xml_element(elements, "title", title_val)
    elements << "<link href=\"#{escape_xml(link_val)}\" rel=\"alternate\"/>" if link_val
    elements << "<id>#{escape_xml(id_val || link_val)}</id>" if link_val
    add_xml_time_element(elements, "updated", instance_variable_get(:@updated), :iso8601)
    add_xml_element(elements, "subtitle", instance_variable_get(:@subtitle))
    author_val = instance_variable_get(:@author)
    elements << "<author><name>#{escape_xml(author_val)}</name></author>" if author_val
    add_xml_element(elements, "generator", instance_variable_get(:@generator))
    elements
  end

  # @rbs (Hash[Symbol, untyped]) -> Array[String]
  def atom_entry_elements(item)
    elements = ["<entry>"] #: Array[String]
    elements << "<title>#{escape_xml(item[:title])}</title>" if item[:title]
    elements << "<link href=\"#{escape_xml(item[:link])}\" rel=\"alternate\"/>" if item[:link]
    elements << "<id>#{escape_xml(item[:id] || item[:guid] || item[:link])}</id>" if item[:id] || item[:guid] || item[:link]
    elements << "<updated>#{item[:updated].iso8601}</updated>" if item[:updated].is_a?(Time)
    atom_entry_published(elements, item)
    elements << "<summary><![CDATA[#{item[:summary] || item[:description]}]]></summary>" if item[:summary] || item[:description]
    elements << "<content><![CDATA[#{item[:content]}]]></content>" if item[:content]
    elements << "<author><name>#{escape_xml(item[:author])}</name></author>" if item[:author]
    elements << "<category term=\"#{escape_xml(item[:category])}\"/>" if item[:category]
    elements << "</entry>"
    elements
  end

  # @rbs (Array[String], Hash[Symbol, untyped]) -> void
  def atom_entry_published(elements, item)
    if item[:published].is_a?(Time)
      elements << "<published>#{item[:published].iso8601}</published>"
    elsif item[:pubDate].is_a?(Time)
      elements << "<published>#{item[:pubDate].iso8601}</published>"
    end
  end

  # @rbs (String) -> String
  def unescape(content)
    result = if content =~ %r{([^-_.!~*'()a-zA-Z\d;/?:@&=+$,\[\]]%)}
               CGI.unescape(content)
             else
               content
             end.gsub(/(<!\[CDATA\[|\]\]>)/, "").strip

    result.encode(Encoding::UTF_8)
  end
end

class SimpleRSSError < StandardError
end
