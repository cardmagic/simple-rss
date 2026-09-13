require "test_helper"

class NormalizedEntriesTest < Test::Unit::TestCase
  def test_equivalent_rss_and_atom_entries_share_one_interface
    entries = %w[rss atom].map { |format| fixture(format).normalized_entries.first }

    entries.each do |entry|
      assert_equal "opaque:%2F:001", entry.identifier
      assert_equal "Ruby & feeds", entry.title
      assert_equal "https://example.com/blog/article?one=1&two=2", entry.url
      assert_equal Time.utc(2026, 9, 12, 10), entry.published_at
      assert_equal Time.utc(2026, 9, 13, 11), entry.updated_at
      assert_equal "<p>Full &amp; complete.</p>", entry.content_html
      assert_nil entry.content_text
      assert_equal "<p>A summary.</p>", entry.summary
      assert_equal :html, entry.summary_type
      assert_equal %w[ruby feeds], entry.categories
      assert_equal(["https://example.com/audio/one.mp3", "https://example.com/images/two.png"], entry.attachments.map { |attachment| attachment[:url] })
      assert_equal(%w[audio/mpeg image/png], entry.attachments.map { |attachment| attachment[:media_type] })
      assert_equal([1234, 4321], entry.attachments.map { |attachment| attachment[:size_in_bytes] })
      assert_empty entry.issues
    end
  end

  def test_normalization_preserves_raw_access_serialization_and_configuration
    feed = fixture("atom")
    before = [feed.source.dup, feed.to_hash, feed.to_json, feed.to_xml, SimpleRSS.item_tags.dup, SimpleRSS.feed_tags.dup]

    first = feed.normalized_entries.first
    second = feed.normalized_entries.first

    assert_equal first.to_h, second.to_h
    assert_equal feed.first, first.raw
    assert_not_same feed.first, first.raw
    assert_equal before, [feed.source, feed.to_hash, feed.to_json, feed.to_xml, SimpleRSS.item_tags, SimpleRSS.feed_tags]
    assert_raise(FrozenError) { first.categories << "changed" }
    assert_raise(FrozenError) { first.raw[:title].replace("changed") }
    assert_equal "Ruby &amp; feeds", feed.first.title
  end

  def test_link_selection_honors_default_and_iana_relations_and_preserves_metadata
    entry = atom_entry(<<~XML)
      <link rel="self" href="https://example.com/api/1"/>
      <link type="application/pdf" href="https://example.com/article.pdf"/>
      <link rel="http://www.iana.org/assignments/relation/alternate" type="text/html; charset=utf-8"
        title="Web &amp; mobile" hreflang="en" href="https://example.com/article">
        <extra href="https://wrong.example.com/"/>
      </link>
    XML

    assert_equal "https://example.com/article", entry.url
    assert_equal 3, entry.links.size
    assert_equal "Web & mobile", entry.links.last[:raw][:attributes]["title"]
    assert_equal "en", entry.links.last[:raw][:attributes]["hreflang"]
    assert_include entry.links.last[:raw][:content], "wrong.example.com"
    assert_nil atom_entry('<link rel="self" href="https://example.com/api/1"/>').url
    assert_equal "https://example.com/default", atom_entry('<link href="https://example.com/default"/>').url
  end

  def test_relative_urls_use_source_url_and_each_xml_base_without_changing_identifiers
    source = <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom" xml:base="../blog/">
        <title>Base URLs</title>
        <entry xml:base="posts/">
          <id>../opaque%2Fid</id>
          <link xml:base="../../articles/" href="one?tag=ruby&amp;page=2#section"/>
          <link rel="enclosure" href="//cdn.example.com/one.mp3"/>
        </entry>
      </feed>
    XML
    feed = SimpleRSS.parse(source, source_url: "https://example.com/feeds/current.xml")
    entry = feed.normalized_entries.first

    assert_equal "https://example.com/articles/one?tag=ruby&page=2#section", entry.url
    assert_equal "https://cdn.example.com/one.mp3", entry.attachments.first[:url]
    assert_equal "../opaque%2Fid", entry.identifier
    assert_equal "https://override.example.com/articles/one?tag=ruby&page=2#section",
                 feed.normalized_entries(source_url: "https://override.example.com/feeds/current.xml").first.url
    assert_equal "https://example.com/feeds/current.xml", feed.source_url
  end

  def test_relative_and_invalid_urls_remain_inspectable_without_a_usable_base
    entry = atom_entry('<link href="../article"/>')
    assert_equal "../article", entry.url
    assert_include entry.issues, { field: :url, code: :relative_url_without_base, value: "../article", source: "link" }

    entry = atom_entry('<link href="http://[broken"/>')
    assert_equal "http://[broken", entry.url
    assert_equal :invalid_url, entry.issues.first[:code]

    entry = atom_entry('<link xml:base="http://[broken" href="article"/>', source_url: "https://example.com/")
    assert_equal "article", entry.url
    assert_include entry.issues.map { |issue| issue[:field] }, :base_url
  end

  def test_publication_and_update_dates_remain_distinct_and_invalid_dates_are_preserved
    entry = atom_entry("<published>not-a-date</published><updated>2026-09-13T11:00:00Z</updated>")

    assert_nil entry.published_at
    assert_equal Time.utc(2026, 9, 13, 11), entry.updated_at
    assert_equal entry.updated_at, entry.effective_at
    assert_equal "not-a-date", entry.raw[:published]
    assert_include entry.issues, { field: :published_at, code: :invalid_date, value: "not-a-date", source: "published" }
    assert_nil atom_entry("<updated>broken</updated>").effective_at

    entry = rss_entry("<pubDate>broken</pubDate><dc:date>2026-09-12T10:00:00Z</dc:date><modified>broken too</modified>")
    assert_equal Time.utc(2026, 9, 12, 10), entry.published_at
    assert_nil entry.updated_at
    assert_equal "dc:date", entry.field_sources[:published_at]
    assert_equal 2, entry.issues.size
  end

  def test_atom_content_types_preserve_text_html_cdata_and_summary_boundaries
    entry = atom_entry("<content>&lt;b&gt;literal &amp; text&lt;/b&gt;</content><summary>Short version</summary>")
    assert_equal "<b>literal & text</b>", entry.content_text
    assert_nil entry.content_html
    assert_equal "Short version", entry.summary
    assert_equal :text, entry.summary_type

    entry = atom_entry('<content type="html"><![CDATA[<p>A &amp; B</p>]]></content>')
    assert_equal "<p>A &amp; B</p>", entry.content_html
    assert_nil entry.content_text
    assert_equal "content", entry.field_sources[:content_html]

    entry = atom_entry('<summary type="html">&lt;p&gt;Summary only&lt;/p&gt;</summary>')
    assert_nil entry.content_html
    assert_nil entry.content_text
    assert_equal "<p>Summary only</p>", entry.summary
    assert_nil rss_entry("<description>Summary only</description>").content_text
  end

  def test_external_unsupported_and_invalid_text_content_do_not_become_plain_text
    entry = atom_entry('<content type="text/plain" src="https://example.com/full.txt">Ignored inline body</content>')
    assert_equal "https://example.com/full.txt", entry.content_url
    assert_nil entry.content_text
    assert_nil entry.content_html

    entry = atom_entry('<content type="application/octet-stream">YWJj</content>')
    assert_nil entry.content_text
    assert_nil entry.content_html
    assert_equal "YWJj", entry.raw[:content]
    assert_equal :unsupported_content_type, entry.issues.first[:code]

    entry = atom_entry('<content type="text"><b>Actual markup</b></content>')
    assert_nil entry.content_text
    assert_equal :unexpected_markup, entry.issues.first[:code]
  end

  def test_xhtml_content_excludes_its_container_and_retains_its_base
    entry = atom_entry(<<~XML)
      <content type="xhtml" xml:base="https://example.com/articles/">
        <div xmlns="http://www.w3.org/1999/xhtml"><p>A &amp; B <a href="one">link</a></p></div>
      </content>
    XML
    assert_equal '<p>A &amp; B <a href="one">link</a></p>', entry.content_html
    assert_equal "https://example.com/articles/", entry.content_base_url
    assert_nil entry.content_text
    assert_empty entry.issues

    entry = atom_entry('<content type="xhtml"><div xmlns="urn:foreign">Wrong namespace</div></content>')
    assert_nil entry.content_html
    assert_equal :invalid_xhtml, entry.issues.first[:code]
  end

  def test_custom_full_text_mappings_are_local_and_take_precedence_without_global_tags
    source = <<~XML
      <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:body="urn:example:body">
        <channel><title>Custom content</title><item>
          <description>Summary</description>
          <content:encoded><![CDATA[<p>Default body</p>]]></content:encoded>
          <full-text><![CDATA[<p>Complete body</p>]]></full-text>
          <body:plain>Complete text</body:plain>
          <extension><full-text>Nested body</full-text></extension>
        </item></channel>
      </rss>
    XML
    tags = [SimpleRSS.feed_tags.dup, SimpleRSS.item_tags.dup]
    feed = SimpleRSS.parse(source)
    entry = feed.normalized_entries(mappings: { content_html: "full-text", content_text: "{urn:example:body}plain" }).first

    assert_equal "<p>Complete body</p>", entry.content_html
    assert_equal "Complete text", entry.content_text
    assert_equal "Summary", entry.summary
    assert_equal "full-text", entry.field_sources[:content_html]
    assert_equal "body:plain", entry.field_sources[:content_text]
    assert_include entry.raw_xml, "<full-text>"
    assert_equal "<p>Default body</p>", feed.normalized_entries.first.content_html
    assert_equal "<p>Default body</p>", SimpleRSS.parse(source).normalized_entries.first.content_html
    assert_equal tags, [SimpleRSS.feed_tags, SimpleRSS.item_tags]
  end

  def test_categories_preserve_labels_schemes_duplicates_and_source_aware_keywords
    entry = fixture("atom").normalized_entries.first
    assert_equal %w[ruby feeds], entry.categories
    assert_equal(%w[ruby feeds ruby], entry.category_details.map { |category| category[:term] })
    assert_equal "Ruby language", entry.category_details.first[:label]
    assert_equal "urn:topics", entry.category_details.first[:scheme]
    assert_equal "ruby", entry.category_details.first[:raw][:attributes]["term"]

    source = <<~XML
      <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:media="http://search.yahoo.com/mrss/">
        <channel><title>Keywords</title><item>
          <category>ruby, rails</category><dc:subject>ruby; feeds</dc:subject>
          <media:keywords>audio, video</media:keywords><keywords>one | two</keywords>
        </item></channel>
      </rss>
    XML
    feed = SimpleRSS.parse(source)
    assert_equal ["ruby, rails", "ruby; feeds", "audio, video"], feed.normalized_entries.first.categories
    mappings = { categories: [{ tag: "dc:subject", separator: ";" }, { tag: "keywords", separator: "|" }] }
    assert_equal ["ruby, rails", "ruby", "feeds", "audio, video", "one", "two"], feed.normalized_entries(mappings: mappings).first.categories
  end

  def test_multiple_attachments_keep_attributes_and_invalid_numbers_with_their_urls
    entry = rss_entry(<<~XML)
      <enclosure url="https://example.com/one" type="audio/mpeg" length="0"/>
      <media:group xml:base="https://example.com/media/">
        <media:content url="two" type="video/mp4" fileSize="123" duration="12.5"/>
        <media:content url="three" type="image/png" fileSize="no-size" duration="forever"/>
      </media:group>
      <description><![CDATA[<enclosure url="https://wrong.example.com/"/>]]></description>
    XML
    first, second, third = entry.attachments
    assert_equal 3, entry.attachments.size
    assert_equal 0, first[:size_in_bytes]
    assert_equal "https://example.com/media/two", second[:url]
    assert_equal "video/mp4", second[:media_type]
    assert_equal 123, second[:size_in_bytes]
    assert_equal 12.5, second[:duration_in_seconds]
    assert_equal "https://example.com/media/three", third[:url]
    assert_nil third[:size_in_bytes]
    assert_nil third[:duration_in_seconds]
    assert_equal "no-size", third[:raw][:attributes]["fileSize"]
    assert_equal "forever", third[:raw][:attributes]["duration"]
    assert_equal(%i[size_in_bytes duration_in_seconds], entry.issues.map { |issue| issue[:field] })
  end

  def test_single_attachment_can_use_itunes_duration_without_applying_it_to_multiple_files
    entry = rss_entry('<enclosure url="https://example.com/one"/><itunes:duration>1:02:03</itunes:duration>')
    assert_equal 3723, entry.attachments.first[:duration_in_seconds]
    assert_equal "itunes:duration", entry.attachments.first[:raw_duration][:name]

    entry = rss_entry('<enclosure url="https://example.com/one"/><itunes:duration>1:99</itunes:duration>')
    assert_nil entry.attachments.first[:duration_in_seconds]
    assert_equal :invalid_number, entry.issues.first[:code]

    entry = rss_entry('<enclosure url="https://example.com/one"/><enclosure url="https://example.com/two"/><itunes:duration>42</itunes:duration>')
    assert_equal([nil, nil], entry.attachments.map { |attachment| attachment[:duration_in_seconds] })
  end

  def test_nested_foreign_and_commented_metadata_cannot_supply_normalized_fields
    entry = atom_entry(<<~XML)
      <!-- <link href="https://wrong.example.com/comment"/><category term="comment"/> -->
      <![CDATA[<content type="html">Wrong body</content>]]>
      <source><id>Wrong id</id><link href="https://wrong.example.com/source"/><category term="source"/></source>
      <content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml"><link href="https://wrong.example.com/body"/></div></content>
      <id xmlns="urn:foreign">Foreign id</id>
      <link xmlns="urn:foreign" href="https://wrong.example.com/foreign"/>
      <category xmlns="" term="reset">Reset</category>
      <published xmlns="urn:foreign">2026-01-01T00:00:00Z</published>
      <id>Actual id</id><category term="actual"/>
    XML
    assert_equal "Actual id", entry.identifier
    assert_nil entry.url
    assert_nil entry.published_at
    assert_equal ["actual"], entry.categories
    assert_empty entry.attachments
    assert_empty entry.links
  end

  def test_entry_order_and_deduplication_keep_original_xml_bound_to_the_correct_hash
    source = <<~XML
      <rss version="2.0"><channel><title>Identical raw items</title>
        <item><guid>same</guid><full-text>First body</full-text></item>
        <item><guid>same</guid><full-text>Second body</full-text></item>
      </channel></rss>
    XML
    feed = SimpleRSS.parse(source)
    mappings = { content_text: "full-text" }
    assert_equal ["First body", "Second body"], feed.normalized_entries(mappings: mappings).map(&:content_text)
    feed.items.reverse!
    assert_equal ["Second body", "First body"], feed.normalized_entries(mappings: mappings).map(&:content_text)
    feed.dedupe
    assert_equal ["Second body"], feed.normalized_entries(mappings: mappings).map(&:content_text)
  end

  def test_empty_fields_do_not_invent_identity_content_dates_or_collections
    entry = atom_entry('<title></title><category term=" "/><link href=""/>')
    assert_nil entry.identifier
    assert_nil entry.url
    assert_nil entry.title
    assert_nil entry.published_at
    assert_nil entry.updated_at
    assert_nil entry.content_html
    assert_nil entry.content_text
    assert_nil entry.summary
    assert_empty entry.categories
    assert_empty entry.attachments
  end

  def test_invalid_mapping_configuration_fails_with_clear_errors
    feed = fixture("rss")
    [nil, { unknown: "tag" }, { content_html: [] }, { content_text: "" }, { categories: "keywords" },
     { categories: [{ tag: "keywords", separator: "" }] }, { categories: [{ tag: nil }] }].each do |mappings|
      assert_raise(ArgumentError) { feed.normalized_entries(mappings: mappings) }
    end
  end

  def test_rdf_item_bases_and_namespaces_do_not_inherit_from_a_sibling_channel
    source = <<~XML
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/"
        xmlns:date="http://purl.org/dc/elements/1.1/" xml:base="https://example.com/">
        <channel xml:base="wrong/" xmlns:date="urn:foreign"><title>Example</title></channel>
        <item><title>First</title><link>article</link><date:date>2026-09-12T10:00:00Z</date:date><date:subject>ruby</date:subject></item>
      </rdf:RDF>
    XML
    entry = SimpleRSS.parse(source).normalized_entries.first
    assert_equal "https://example.com/article", entry.url
    assert_equal Time.utc(2026, 9, 12, 10), entry.published_at
    assert_equal ["ruby"], entry.categories
  end

  def test_plain_xml_text_ignores_comments_and_processing_instructions
    entry = atom_entry("<id>opaque<!-- not identity -->id</id><content>Before<!-- not text -->after<?note ignored?></content>")
    assert_equal "opaqueid", entry.identifier
    assert_equal "Beforeafter", entry.content_text
  end

  def test_atom_authors_inherit_from_source_then_feed_and_keep_uri_bases
    source = <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom" xml:base="https://example.com/">
        <title>Authors</title>
        <author><name>Editorial team</name><uri>about</uri></author>
        <entry><id>one</id></entry>
        <entry><id>two</id><source xml:base="source/"><author><name>Source team</name><uri>about</uri></author></source></entry>
        <entry><id>three</id><author><name>Entry team</name><uri>entry</uri></author><author><name>Guest team</name></author></entry>
      </feed>
    XML
    entries = SimpleRSS.parse(source).normalized_entries
    assert_equal(["Editorial team"], entries[0].authors.map { |author| author[:name] })
    assert_equal "https://example.com/about", entries[0].authors.first[:url]
    assert_equal(["Source team"], entries[1].authors.map { |author| author[:name] })
    assert_equal "https://example.com/source/about", entries[1].authors.first[:url]
    assert_equal(["Entry team", "Guest team"], entries[2].authors.map { |author| author[:name] })
  end

  def test_prefixed_xhtml_preserves_content_and_the_div_base_without_prefixing_html_tags
    entry = atom_entry(<<~XML)
      <content type="xhtml" xml:base="https://example.com/">
        <html:div xmlns:html="http://www.w3.org/1999/xhtml" xml:base="articles/">
          <html:p>Read <html:a href="one">this</html:a> &amp; more.</html:p>
        </html:div>
      </content>
    XML
    assert_equal '<p>Read <a href="one">this</a> &amp; more.</p>', entry.content_html
    assert_equal "https://example.com/articles/", entry.content_base_url
    assert_equal "content", entry.field_sources[:content_html]
    assert_include entry.raw_xml, "<html:div"
  end

  def test_content_media_type_parameters_and_rss_link_attributes_do_not_change_meaning
    entry = atom_entry('<content type="text/html; charset=utf-8">&lt;p&gt;Body&lt;/p&gt;</content>')
    assert_equal "<p>Body</p>", entry.content_html
    assert_nil entry.content_text

    entry = rss_entry('<link rel="self">https://example.com/article</link>')
    assert_equal "https://example.com/article", entry.url
  end

  private

  def fixture(format)
    SimpleRSS.parse(File.read(File.join(__dir__, "../data/normalized_#{format}.xml")))
  end

  def atom_entry(content, options = {})
    SimpleRSS.parse('<feed xmlns="http://www.w3.org/2005/Atom"><title>Example</title><entry>' + content + "</entry></feed>", options).normalized_entries.first
  end

  def rss_entry(content)
    source = <<~XML
      <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:media="http://search.yahoo.com/mrss/"
        xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
        <channel><title>Example</title><item>#{content}</item></channel>
      </rss>
    XML
    SimpleRSS.parse(source).normalized_entries.first
  end
end
