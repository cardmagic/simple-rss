# rbs_inline: enabled

require "cgi"
require "time"

class SimpleRSS
  VERSION = "1.3.3".freeze

  # @rbs @items: Array[Hash[Symbol, untyped]]
  # @rbs @source: String
  # @rbs @options: Hash[Symbol, untyped]

  attr_reader :items, :source
  alias entries items

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

    @@feed_tags.each do |tag|
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
        parse_item_tag(item, tag, match[3])
      end
      item.define_singleton_method(:method_missing) { |name, *| self[name] }
      @items << item
    end
  end

  # @rbs (Hash[Symbol, untyped], Symbol, String?) -> void
  def parse_item_tag(item, tag, content)
    return if content.nil?

    tag_str = tag.to_s

    return parse_rel_tag(item, tag_str, content) if tag_str.include?("+")
    return parse_attr_tag(item, tag_str, content) if tag_str.include?("#")

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

  # @rbs (Hash[Symbol, untyped], String, String) -> void
  def parse_attr_tag(item, tag_str, content)
    tag, attrib = tag_str.split("#")
    return unless tag && attrib

    content =~ %r{<(rss:|atom:)?#{tag}(.*?)#{attrib}=['"](.*?)['"](.*?)>(.*?)</(rss:|atom:)?#{tag}>}mi ||
      content =~ %r{<(rss:|atom:)?#{tag}(.*?)#{attrib}=['"](.*?)['"](.*?)/\s*>}mi

    return unless Regexp.last_match(3)

    item[clean_tag("#{tag}_#{attrib}")] = clean_content(tag.to_sym, attrib, Regexp.last_match(3))
  end

  # @rbs (Hash[Symbol, untyped], Symbol, String) -> void
  def parse_simple_tag(item, tag, content)
    content =~ %r{<(rss:|atom:)?#{tag}(.*?)>(.*?)</(rss:|atom:)?#{tag}>}mi ||
      content =~ %r{<(rss:|atom:)?#{tag}(.*?)/\s*>}mi

    return unless Regexp.last_match(2) || Regexp.last_match(3)

    item[clean_tag(tag)] = clean_content(tag, Regexp.last_match(2), Regexp.last_match(3))
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

  # @rbs (String) -> String
  def unescape(content)
    if content =~ %r{([^-_.!~*'()a-zA-Z\d;/?:@&=+$,\[\]]%)}
      CGI.unescape(content)
    else
      content
    end.gsub(/(<!\[CDATA\[|\]\]>)/, "").strip
  end
end

class SimpleRSSError < StandardError
end
