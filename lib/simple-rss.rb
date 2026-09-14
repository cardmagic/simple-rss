# rbs_inline: enabled

require "cgi"
require "time"

class SimpleRSS # rubocop:disable Metrics/ClassLength
  # @rbs skip
  include Enumerable

  # @rbs!
  #   include Enumerable[Hash[Symbol, untyped]]

  VERSION = "2.3.0".freeze

  # @rbs @items: Array[Hash[Symbol, untyped]]
  # @rbs @source: String
  # @rbs @options: Hash[Symbol, untyped]
  # @rbs @json_feed: JsonFeed?
  # @rbs @etag: String?
  # @rbs @last_modified: String?
  # @rbs @entry_contexts: Hash[Hash[Symbol, untyped], Hash[Symbol, untyped]]

  attr_reader :items #: Array[Hash[Symbol, untyped]]
  attr_reader :source #: String
  attr_reader :etag #: String?
  attr_reader :last_modified #: String?
  attr_reader :source_url #: String?
  attr_reader :raw_json #: Hash[String, untyped]?
  attr_reader :home_page_url, :feed_url, :favicon, :next_url, :user_comment #: String?
  attr_reader :authors, :hubs #: untyped
  attr_reader :expired #: bool?
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
    media:description
    enclosure#url enclosure#type enclosure#length
    itunes:duration itunes:image#href
  ]

  # @rbs (untyped, ?Hash[Symbol, untyped]) -> void
  def initialize(source, options = {})
    @source = source.respond_to?(:read) ? source.read.to_s : source.to_s
    @items = [] #: Array[Hash[Symbol, untyped]]
    @options = {} #: Hash[Symbol, untyped]
    @options.update(options)
    @source_url = options[:source_url]
    @json_feed = nil
    @raw_json = nil
    @entry_contexts = {} #: Hash[Hash[Symbol, untyped], Hash[Symbol, untyped]]
    @entry_contexts.compare_by_identity

    parse
  end

  # @rbs () -> SimpleRSS
  def channel
    self
  end
  alias feed channel

  # @rbs (?source_url: String?, ?mappings: Hash[Symbol, untyped]) -> Array[NormalizedEntry]
  def normalized_entries(source_url: nil, mappings: {})
    json_feed = @json_feed
    raise ArgumentError, "XML mappings are not supported for JSON Feed" if json_feed && !mappings.empty?
    return items.map { |item| json_feed.normalized_entry(item, source_url: source_url || @source_url) } if json_feed

    EntryNormalizer.validate_mappings(mappings)
    feed_authors = normalized_feed_authors
    items.map do |item|
      context = @entry_contexts[item] || raise(SimpleRSSError, "Cannot normalize an item without its original XML source")
      element = XmlElement.new(context[:name], context[:attributes], context[:content], context[:parent])
      EntryNormalizer.new(element, item, source_url: source_url || @source_url, mappings: mappings,
                                         raw_xml: context[:xml], feed_authors: feed_authors).entry
    end
  end

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
    sorted_items_by_date(items).first(count)
  end

  # @rbs () -> Symbol
  def feed_type
    return :json_feed if @json_feed

    atom_namespaced_feed = source.match?(/<(atom:)?feed\b[^>]*xmlns(:\w+)?=['"][^'"]*atom/i)
    return :atom if atom_namespaced_feed
    return :rss2 if source.match?(/<rss[^>]*version=['"]2/i)
    return :rss1 if source.match?(/<rdf:RDF/i)
    return :rss09 if source.match?(/<rss[^>]*version=['"]0\.9/i)

    :unknown
  end

  # @rbs () -> bool
  def valid?
    return true if @json_feed

    return false if items.empty?

    title_value = instance_variable_get(:@title)
    link_value = instance_variable_get(:@link)
    return true if title_value || link_value

    false
  end

  # @rbs (Time) -> Array[Hash[Symbol, untyped]]
  def items_since(time)
    items.select do |item|
      date = item_date(item)
      date && date > time
    end
  end

  # @rbs (String) -> Array[Hash[Symbol, untyped]]
  def items_by_category(name)
    query = name.to_s.downcase

    items.select do |item|
      category = item[:category]
      next false if category.nil?

      category_matches_query?(category, query)
    end
  end

  # @rbs (String) -> Array[Hash[Symbol, untyped]]
  def search(query)
    pattern = Regexp.new(Regexp.escape(query.to_s), Regexp::IGNORECASE)

    items.select do |item|
      searchable_fields(item).any? { |field| field.to_s.match?(pattern) }
    end
  end

  # @rbs (*SimpleRSS) -> Array[Hash[Symbol, untyped]]
  def merge(*feeds)
    all_items = [items, *feeds.map(&:items)].flatten
    keyed_items, unkeyed_items = all_items.partition { |item| !item_key(item).nil? }
    dedupe_items(sorted_items_by_date(keyed_items) + unkeyed_items)
  end

  # @rbs (SimpleRSS) -> Hash[Symbol, Array[Hash[Symbol, untyped]]]
  def diff(other)
    other_keys = keyed_item_set(other.items)
    current_keys = keyed_item_set(items)

    {
      added: select_new_keyed_items(other.items, current_keys),
      removed: select_new_keyed_items(items, other_keys)
    }
  end

  # @rbs () -> self
  def dedupe
    @items = dedupe_items(items)
    self
  end

  # @rbs () -> Array[Hash[Symbol, untyped]]
  def enclosures
    items.filter_map do |item|
      enclosure_url = item[:enclosure_url]
      next if blank_value?(enclosure_url)

      {
        url: enclosure_url,
        type: item[:enclosure_type],
        length: item[:enclosure_length],
        item: item
      }
    end
  end

  # @rbs () -> Array[String]
  def images
    items.flat_map { |item| item_image_urls(item) }.uniq
  end

  # @rbs (?Hash[Symbol, untyped]) -> Hash[Symbol, untyped]
  def as_json(_options = {})
    raw_json = @raw_json
    hash = raw_json ? raw_json.transform_keys(&:to_sym) : {} #: Hash[Symbol, untyped]

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
    raise SimpleRSSError, "JSON Feed to XML conversion is not supported" if @json_feed

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

    # @rbs (untyped, ?Hash[Symbol, untyped]) -> bool
    def valid?(source, options = {})
      parse(source, options)
      true
    rescue StandardError
      false
    end

    # @rbs (*SimpleRSS) -> Array[Hash[Symbol, untyped]]
    def merge(*feeds)
      first_feed = feeds.first
      return [] if first_feed.nil?

      first_feed.merge(*feeds.drop(1))
    end

    # Fetch and parse a feed from a URL
    # Returns nil if conditional GET returns 304 Not Modified
    #
    # @rbs (String, ?Hash[Symbol, untyped]) -> SimpleRSS?
    def fetch(url, options = {})
      require "net/http"
      require "uri"

      require_relative "simple-rss/http_client"
      response, final_uri = HTTPClient.new(options).get(url)

      return nil if response.is_a?(Net::HTTPNotModified)

      raise SimpleRSSError, "HTTP #{response.code}: #{response.message}" unless response.is_a?(Net::HTTPSuccess)

      body = (response.body || "").force_encoding(Encoding::UTF_8)
      feed = parse(body, options.merge(source_url: final_uri.to_s))
      feed.instance_variable_set(:@etag, response["ETag"])
      feed.instance_variable_set(:@last_modified, response["Last-Modified"])
      feed
    end

    # @rbs (String, ?Hash[Symbol, untyped]) -> Array[Hash[Symbol, untyped]]
    def discover(url, options = {})
      require_relative "simple-rss/discovery"
      Discovery.new(options).discover(url)
    end
  end

  DATE_TAGS = %i[pubDate lastBuildDate published updated expirationDate modified dc:date].freeze
  STRIP_HTML_TAGS = %i[author contributor skipHours skipDays].freeze
  ATOM_NAMESPACE = "http://www.w3.org/2005/Atom".freeze
  RSS_NAMESPACES = [nil, "", "http://purl.org/rss/1.0/", "http://my.netscape.com/rdf/simple/0.9/"].freeze
  XML_TAG_PATTERN = %r{<!--.*?-->|<!\[CDATA\[.*?\]\]>|<\?.*?\?>|<(/?)([\w:.-]+)((?:[^<>"']|"[^"]*"|'[^']*')*)>}m

  private

  # @rbs () -> Array[XmlElement]
  def normalized_feed_authors
    document = XmlElement.new("", "", @source, { namespaces: {}, base_urls: [] })
    feed = document.children.find { |element| element.matches?("feed", ATOM_NAMESPACE) }
    return [] unless feed

    feed.children.select { |element| element.matches?("author", ATOM_NAMESPACE) }
  end

  # @rbs () -> void
  def parse
    prefix = @source.b.sub(/\A\xEF\xBB\xBF/n, "").lstrip
    return parse_xml unless prefix.match?(/\A(?:[\{\["0-9-]|true\b|false\b|null\b)/n)

    json_feed = JsonFeed.new(@source)
    @json_feed = json_feed
    @raw_json = json_feed.document
    JsonFeed::FEED_FIELDS.each do |field|
      instance_variable_set("@#{field}", json_feed.document[field])
      self.class.attr_reader(field)
    end
    @link = json_feed.document["home_page_url"]
    self.class.attr_reader(:link)
    @items = json_feed.items
    @items.each do |item|
      item.define_singleton_method(:method_missing) { |name, *_args| self[name] }
      add_item_media_helpers(item)
    end
  end

  # @rbs () -> void
  def parse_xml
    raise SimpleRSSError, "Poorly formatted feed" unless @source =~ %r{<(channel|feed).*?>.*?</(channel|feed)>|<(channel|feed)\b[^>]*?/\s*>}mi

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
    namespace_contexts = entry_contexts
    entry_pattern = %r{<(rss:|atom:)?(item|entry)([\s][^>]*)?>(.*?)</(rss:|atom:)?(item|entry)>}mi
    position = 0
    while (match = entry_pattern.match(@source, position))
      position = match.end(0)
      item = {} #: Hash[Symbol, untyped]
      parent_context = namespace_contexts[match.begin(0)]
      namespaces = parent_context && parent_context[:namespaces].merge(namespace_attributes(match[3].to_s))
      @entry_contexts[item] = {
        name: "#{match[1]}#{match[2]}", attributes: match[3].to_s, content: match[4].to_s,
        parent: parent_context || { namespaces: {}, base_urls: [] }, xml: match[0]
      }
      @@item_tags.each do |tag|
        next if tag.to_s.strip.empty?

        if tag == :category
          next unless namespaces

          parse_category_tag(item, match[4].to_s, namespaces, element_namespace("#{match[1]}#{match[2]}", namespaces))
          next
        end

        parse_item_tag(item, tag, match[4], match[3])
      end
      item.define_singleton_method(:method_missing) { |name, *_args| self[name] }
      add_item_media_helpers(item)
      @items << item
    end
  end

  # @rbs (Hash[Symbol, untyped]) -> void
  def add_item_media_helpers(item)
    item.define_singleton_method(:has_media?) do
      [
        self[:media_content_url],
        self[:media_thumbnail_url],
        self[:enclosure_url],
        self[:itunes_image_href]
      ].any? { |value| !value.nil? && !value.to_s.strip.empty? }
    end

    item.define_singleton_method(:media_url) do
      [
        self[:media_content_url],
        self[:media_thumbnail_url],
        self[:enclosure_url],
        self[:itunes_image_href]
      ].find { |value| !value.nil? && !value.to_s.strip.empty? }
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
    tag, rel = tag_str.split("+", 2)
    return unless tag && rel

    value = if tag == "link"
              link_relation_href(content, rel)
            else
              content =~ %r{<(rss:|atom:)?#{tag}(.*?)rel=['"]#{rel}['"](.*?)>(.*?)</(rss:|atom:)?#{tag}>}mi ||
                content =~ %r{<(rss:|atom:)?#{tag}(.*?)rel=['"]#{rel}['"](.*?)/\s*>}mi

              return unless Regexp.last_match(3) || Regexp.last_match(4)

              clean_content(tag.to_sym, Regexp.last_match(3), Regexp.last_match(4))
            end
    return if value.nil?

    item[clean_tag("#{tag}+#{rel}")] = value
    item[clean_tag("#{tag}_#{rel}")] = value
  end

  # @rbs (String, String) -> String?
  def link_relation_href(content, relation)
    attributes = entry_link_attributes(content).find { |link| link["rel"]&.casecmp?(relation) }
    return unless attributes

    attributes["href"]
  end

  # @rbs (String) -> Array[Hash[String, String]]
  def entry_link_attributes(content)
    child_elements(content).filter_map do |tag, attributes, _body|
      next unless %w[link atom:link rss:link].include?(tag.downcase)

      xml_attributes(attributes).transform_keys(&:downcase)
    end
  end

  # @rbs (String) -> Array[[String, String, String?]]
  def child_elements(content)
    XmlElement.child_elements(content)
  end

  # @rbs (Hash[Symbol, untyped], String, Hash[String, String], String?) -> void
  def parse_category_tag(item, content, namespaces, entry_namespace)
    values = child_elements(content).filter_map do |tag, raw_attributes, body|
      next unless tag.split(":").last&.casecmp?("category")

      attributes = xml_attributes(raw_attributes)
      namespace = element_namespace(tag, namespaces.merge(namespace_attributes(raw_attributes)))
      if namespace == ATOM_NAMESPACE
        term = CGI.unescapeHTML(attributes["term"].to_s).strip
        next term unless term.empty?

        next
      end

      next if entry_namespace == ATOM_NAMESPACE || !RSS_NAMESPACES.include?(namespace)
      next if tag.include?(":") && namespace.nil?
      next if body.nil? && (array_tag?(:category) || !raw_attributes.rstrip.end_with?("/"))

      unescape(body.to_s)
    end
    return if values.empty?

    item[:category] = array_tag?(:category) ? values : values.first
  end

  # @rbs () -> Hash[Integer, Hash[Symbol, untyped]]
  def entry_contexts
    contexts = {} #: Hash[Integer, Hash[Symbol, untyped]]
    scopes = [{ namespaces: {}, base_urls: [] }] #: Array[Hash[Symbol, untyped]]
    position = 0

    while (token = XML_TAG_PATTERN.match(@source, position))
      position = token.end(0)
      attributes = token[3]
      next unless attributes

      if token[1] == "/"
        scopes.pop if scopes.size > 1
        next
      end

      parent = scopes.fetch(-1)
      tag = token[2].to_s.split(":").last
      contexts[token.begin(0).to_i] = parent if %w[item entry].include?(tag&.downcase)
      base_url = xml_attributes(attributes)["xml:base"]
      base_urls = parent[:base_urls].dup
      base_urls << CGI.unescapeHTML(base_url) if base_url
      context = {
        namespaces: parent[:namespaces].merge(namespace_attributes(attributes)),
        base_urls: base_urls
      }
      scopes << context unless attributes.rstrip.end_with?("/")
    end

    contexts
  end

  # @rbs (String) -> Hash[String, String]
  def namespace_attributes(attributes)
    xml_attributes(attributes)
      .select { |name, _value| name == "xmlns" || name.start_with?("xmlns:") }
      .transform_values { |value| CGI.unescapeHTML(value) }
  end

  # @rbs (String, Hash[String, String]) -> String?
  def element_namespace(tag, namespaces)
    key = tag.include?(":") ? "xmlns:#{tag.split(":").first}" : "xmlns"
    namespaces[key]
  end

  # @rbs (String) -> Hash[String, String]
  def xml_attributes(attributes)
    XmlElement.attributes(attributes)
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

  # @rbs (untyped, String) -> bool
  def category_matches_query?(category, query)
    return category.any? { |value| value.to_s.downcase.include?(query) } if category.is_a?(Array)

    category.to_s.downcase.include?(query)
  end

  # @rbs (Hash[Symbol, untyped]) -> Array[untyped]
  def searchable_fields(item)
    [item[:title], item[:description], item[:summary], item[:content]]
  end

  # @rbs (Array[Hash[Symbol, untyped]]) -> Set[String]
  def keyed_item_set(item_list)
    item_list.each_with_object(Set.new) do |item, keys|
      key = item_key(item)
      next if key.nil?

      keys.add(key)
    end
  end

  # @rbs (Array[Hash[Symbol, untyped]], Set[String]) -> Array[Hash[Symbol, untyped]]
  def select_new_keyed_items(item_list, known_keys)
    item_list.select do |item|
      key = item_key(item)
      !key.nil? && !known_keys.include?(key)
    end
  end

  # @rbs (Array[Hash[Symbol, untyped]]) -> Array[Hash[Symbol, untyped]]
  def sorted_items_by_date(item_list)
    item_list.sort_by.with_index do |item, index|
      date = item_date(item)
      [date ? -date.to_r : Float::INFINITY, index]
    end
  end

  # @rbs (Array[Hash[Symbol, untyped]]) -> Array[Hash[Symbol, untyped]]
  def dedupe_items(item_list)
    seen_keys = Set.new

    item_list.each_with_object([]) do |item, unique_items|
      key = item_key(item)

      if key.nil?
        unique_items << item
        next
      end

      next if seen_keys.include?(key)

      seen_keys.add(key)
      unique_items << item
    end
  end

  # @rbs (Hash[Symbol, untyped]) -> String?
  def item_key(item)
    key = item[:guid] || item[:id] || item[:link]
    return nil if key.nil?

    key.to_s
  end

  # @rbs (Hash[Symbol, untyped]) -> Time?
  def item_date(item)
    [item[:pubDate], item[:updated], item[:published]].find { |date| date.is_a?(Time) }
  end

  # @rbs (Hash[Symbol, untyped]) -> Array[String]
  def item_image_urls(item)
    [item[:media_thumbnail_url], item[:media_content_url], item[:itunes_image_href]]
      .compact
      .reject { |url| blank_value?(url) }
  end

  # @rbs (untyped) -> bool
  def blank_value?(value)
    value.to_s.strip.empty?
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

require_relative "simple-rss/xml_element"
require_relative "simple-rss/normalized_entry"
require_relative "simple-rss/json_feed"
require_relative "simple-rss/json_entry_normalizer"
require_relative "simple-rss/entry_normalizer"

class SimpleRSSError < StandardError # rubocop:disable Style/OneClassPerFile
end

require_relative "simple-rss/request_errors"
