# rbs_inline: enabled

require "json"

class SimpleRSS::JsonFeed
  VERSIONS = %w[https://jsonfeed.org/version/1 https://jsonfeed.org/version/1.1].freeze
  FEED_FIELDS = %w[title description home_page_url feed_url icon favicon language author authors expired next_url hubs user_comment].freeze
  FEED_STRINGS = %w[description home_page_url feed_url icon favicon next_url user_comment].freeze
  ITEM_STRINGS = %w[url external_url title summary content_html content_text image banner_image].freeze

  attr_reader :document #: Hash[String, untyped]
  attr_reader :items #: Array[Hash[Symbol, untyped]]

  # @rbs @originals: Hash[Hash[Symbol, untyped], Hash[String, untyped]]

  # @rbs (String) -> void
  def initialize(source)
    source = source.b.sub(/\A\xEF\xBB\xBF/n, "").force_encoding(Encoding::UTF_8)
    raise SimpleRSSError, "Malformed JSON Feed: invalid UTF-8" unless source.valid_encoding?

    @document = JSON.parse(source)
    validate
    freeze_data(@document)
    @originals = {} #: Hash[Hash[Symbol, untyped], Hash[String, untyped]]
    @originals.compare_by_identity
    @items = @document.fetch("items").map do |original|
      item = legacy_item(original)
      @originals[item] = original
      item
    end
  rescue JSON::ParserError, EncodingError => e
    raise SimpleRSSError, "Malformed JSON Feed: #{e.message}"
  end

  # @rbs (Hash[Symbol, untyped], ?source_url: String?) -> SimpleRSS::NormalizedEntry
  def normalized_entry(item, source_url: nil)
    original = @originals[item] || raise(SimpleRSSError, "Cannot normalize an item without its original JSON source")
    SimpleRSS::JsonEntryNormalizer.new(original, document, source_url: source_url).entry
  end

  private

  # @rbs () -> void
  def validate
    check_type(document, Hash, "feed")
    validate_numbers(document)
    required_string(document, "version", "feed")
    raise SimpleRSSError, "Unsupported JSON Feed version: #{document["version"].inspect}" unless VERSIONS.include?(document["version"])

    required_string(document, "title", "feed")
    check_type(document["items"], Array, "items")
    optional_strings(document, FEED_STRINGS, "feed")
    optional_strings(document, ["language"], "feed") if version_1_1?
    validate_expiration
    validate_authors(document, "feed")
    optional_array(document, "hubs", "feed").each_with_index do |hub, index|
      check_type(hub, Hash, "hubs[#{index}]")
      %w[type url].each { |field| required_string(hub, field, "hubs[#{index}]") }
    end
    document["items"].each_with_index { |item, index| validate_item(item, "items[#{index}]") }
  end

  # @rbs (untyped) -> void
  def validate_numbers(value)
    case value
    when Hash then value.each_value { |child| validate_numbers(child) }
    when Array then value.each { |child| validate_numbers(child) }
    when Float
      raise SimpleRSSError, "JSON Feed number exceeds the supported range" unless value.finite?
    end
  end

  # @rbs () -> void
  def validate_expiration
    return unless document.key?("expired")
    return if [true, false].include?(document["expired"])

    raise SimpleRSSError, "JSON Feed feed.expired must be a boolean"
  end

  # @rbs (untyped, String) -> void
  def validate_item(item, path)
    check_type(item, Hash, path)
    identifier = item["id"]
    unless (identifier.is_a?(String) || identifier.is_a?(Numeric)) && !identifier.to_s.strip.empty?
      raise SimpleRSSError, "JSON Feed #{path}.id must be a nonblank string or number"
    end
    unless %w[content_html content_text].any? { |field| item[field].is_a?(String) }
      raise SimpleRSSError, "JSON Feed #{path} requires content_html or content_text"
    end

    optional_strings(item, ITEM_STRINGS, path)
    optional_strings(item, ["language"], path) if version_1_1?
    validate_authors(item, path)
    optional_array(item, "tags", path).each { |tag| check_type(tag, String, "#{path}.tags[]") }
    optional_array(item, "attachments", path).each_with_index do |attachment, index|
      attachment_path = "#{path}.attachments[#{index}]"
      check_type(attachment, Hash, attachment_path)
      %w[url mime_type].each { |field| required_string(attachment, field, attachment_path) }
      optional_strings(attachment, ["title"], attachment_path)
    end
  end

  # @rbs (Hash[String, untyped], String) -> void
  def validate_authors(object, path)
    if version_1_1? && object.key?("authors")
      optional_array(object, "authors", path).each_with_index { |author, index| validate_author(author, "#{path}.authors[#{index}]") }
      return
    end

    validate_author(object["author"], "#{path}.author") if object.key?("author")
  end

  # @rbs (untyped, String) -> void
  def validate_author(author, path)
    check_type(author, Hash, path)
    fields = %w[name url avatar]
    optional_strings(author, fields, path)
    return if fields.any? { |field| author[field].is_a?(String) }

    raise SimpleRSSError, "JSON Feed #{path} requires name, url, or avatar"
  end

  # @rbs (Hash[String, untyped], Array[String], String) -> void
  def optional_strings(object, fields, path)
    fields.each { |field| check_type(object[field], String, "#{path}.#{field}") if object.key?(field) }
  end

  # @rbs (Hash[String, untyped], String, String) -> Array[untyped]
  def optional_array(object, field, path)
    return [] unless object.key?(field)

    check_type(object[field], Array, "#{path}.#{field}")
    object[field]
  end

  # @rbs (Hash[String, untyped], String, String) -> void
  def required_string(object, field, path)
    check_type(object[field], String, "#{path}.#{field}")
  end

  # @rbs (untyped, untyped, String) -> void
  def check_type(value, type, path)
    return if value.is_a?(type)

    raise SimpleRSSError, "JSON Feed #{path} must be a #{type}"
  end

  # @rbs () -> bool
  def version_1_1?
    document["version"] == VERSIONS.last
  end

  # @rbs (Hash[String, untyped]) -> Hash[Symbol, untyped]
  def legacy_item(original)
    entry = SimpleRSS::JsonEntryNormalizer.new(original, document).entry
    attachment = entry.attachments.first || {}
    original.transform_keys(&:to_sym).merge(
      id: entry.identifier, guid: entry.identifier, link: entry.url,
      description: entry.summary || entry.content_text || entry.content_html,
      content: entry.content_html || entry.content_text, category: entry.categories.dup,
      pubDate: entry.published_at || original["date_published"], updated: entry.updated_at || original["date_modified"],
      enclosure_url: attachment[:url], enclosure_type: attachment[:media_type], enclosure_length: attachment[:size_in_bytes],
      media_thumbnail_url: entry.image, media_content_url: entry.banner_image
    )
  end

  # @rbs (untyped) -> void
  def freeze_data(value)
    case value
    when Hash then value.each_value { |child| freeze_data(child) }
    when Array then value.each { |child| freeze_data(child) }
    end
    value.freeze
  end
end
