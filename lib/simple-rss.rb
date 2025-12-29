# rbs_inline: enabled

require "cgi"
require "time"

class SimpleRSS
  VERSION = "2.0.0".freeze

  # @rbs @items: Array[Hash[Symbol, untyped]]
  # @rbs @source: String
  # @rbs @options: Hash[Symbol, untyped]

  attr_reader :items #: Array[Hash[Symbol, untyped]]
  attr_reader :source #: String
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
