require "test_helper"

class CategoryParsingTest < Test::Unit::TestCase
  def test_atom_terms_are_collected_and_filterable
    source = <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Categories</title>
        <entry>
          <title>Ruby news</title>
          <category term="ruby" label="Ruby Language"/>
          <category term="rails" label="Rails"/>
        </entry>
      </feed>
    XML
    feed = SimpleRSS.parse(source, array_tags: [:category])

    assert_equal %w[ruby rails], feed.first.category
    assert_equal [feed.first], feed.items_by_category("ruby")
    assert_equal "ruby", SimpleRSS.parse(source).first.category
  end

  def test_atom_attribute_variants_preserve_order_duplicates_and_source
    source = File.read(File.join(__dir__, "../data/atom_categories.xml"))
    feed = SimpleRSS.parse(source, array_tags: [:category])

    assert_equal ["ruby", "rails", "Ruby & RSS", "ruby"], feed.first.category
    assert_equal [feed.first], feed.items_by_category("RAILS")
    assert_equal [], feed.items_by_category("Human label")
    assert_nil feed[1].category
    assert_equal ["sports"], feed[2].category
    assert_equal source, feed.source
    assert_equal "ruby", SimpleRSS.parse(source).first.category
  end

  def test_atom_scalar_mode_skips_missing_and_blank_terms
    feed = parse_entry(<<~XML)
      <category label="Label only">Not a term</category>
      <category term=" &#32; "/>
      <category term="first"/>
      <category term="second"/>
    XML

    assert_equal "first", feed.first.category
    assert_equal [feed.first], feed.items_by_category("first")
    assert_equal [], feed.items_by_category("second")
  end

  def test_categories_exclude_nested_metadata_content_comments_and_cdata
    feed = parse_entry(<<~XML, array_tags: [:category])
      <source xml:base="https://example.com/"><category term="source"/></source>
      <content type="xhtml"><div><category term="content"/></div></content>
      <extension><category term="extension"/></extension>
      <!-- <category term="comment"/> -->
      <![CDATA[<category term="cdata"/>]]>
      <?example <category term="instruction"/> ?>
      <category term="direct"><category term="nested"/></category>
    XML

    assert_equal ["direct"], feed.first.category
  end

  def test_categories_do_not_borrow_terms_from_neighboring_elements_or_entries
    source = <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Boundaries</title>
        <category term="feed"/>
        <entry>
          <title>First</title>
          <category label="Missing"><extension term="nested"/></category>
          <extension term="neighbor"/>
        </entry>
        <entry><title>Second</title><category term="second"/></entry>
      </feed>
    XML

    [SimpleRSS.parse(source), SimpleRSS.parse(source, array_tags: [:category])].each do |feed|
      assert_nil feed.first.category
      assert_equal [], feed.items_by_category("neighbor")
      assert_equal [feed[1]], feed.items_by_category("second")
    end
  end

  def test_namespace_prefixes_resolve_at_feed_entry_and_category_scope
    source = <<~XML
      <feed xmlns:atom="http://www.w3.org/2005/Atom" xmlns:Topic="http://www.w3.org/2005/Atom">
        <title>Namespace scopes</title>
        <atom:entry xmlns:local="http://www.w3.org/2005/Atom">
          <title>First</title>
          <Topic:category term="feed-scope"/>
          <local:category term="entry-scope"/>
          <inline:category xmlns:inline="http://www.w3.org/2005/At&#111;m" term="category-scope"/>
          <category xmlns="http://www.w3.org/2005/Atom" term="local-default"/>
          <category term="unqualified">Not Atom</category>
        </atom:entry>
      </feed>
    XML
    feed = SimpleRSS.parse(source, array_tags: [:category])

    assert_equal %w[feed-scope entry-scope category-scope local-default], feed.first.category
  end

  def test_namespace_rebinding_and_default_resets_do_not_leak_categories
    source = <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom" xmlns:topic="http://www.w3.org/2005/Atom">
        <title>Rebinding</title>
        <entry xmlns:topic="urn:other">
          <title>First</title>
          <topic:category term="foreign"/>
          <category xmlns="urn:other" term="other">Foreign text</category>
          <category xmlns="" term="reset">Unqualified text</category>
          <topic:category xmlns:topic="http://www.w3.org/2005/Atom" term="restored"/>
        </entry>
        <entry><title>Second</title><topic:category term="inherited"/></entry>
      </feed>
    XML
    feed = SimpleRSS.parse(source, array_tags: [:category])

    assert_equal ["restored"], feed.first.category
    assert_equal ["inherited"], feed[1].category
  end

  def test_exact_element_and_attribute_names_are_required
    feed = parse_entry(<<~XML, array_tags: [:category])
      <categoryish term="wrong-element"/>
      <category data-term="wrong-attribute"/>
      <category label="term='quoted'"/>
      <category xmlns:other="urn:other" other:term="wrong-namespace"/>
      <unknown:category term="undeclared"/>
      <category term="correct"/>
    XML

    assert_equal ["correct"], feed.first.category
  end

  def test_rss_text_cdata_scalar_and_array_filters_remain_compatible
    source = File.read(File.join(__dir__, "../data/rss_categories.xml"))
    scalar_feed = SimpleRSS.parse(source)
    array_feed = SimpleRSS.parse(source, array_tags: [:category])

    assert_equal "Technology", scalar_feed.first.category
    assert_equal ["Technology", "Ruby & RSS", "Technology"], array_feed.first.category
    assert_equal [scalar_feed.first], scalar_feed.items_by_category("tech")
    assert_equal [array_feed.first], array_feed.items_by_category("ruby")
    assert_equal ["Sports"], array_feed[1].category
  end

  def test_rss_categories_exclude_embedded_markup_and_accept_atom_extensions
    source = <<~XML
      <rss version="2.0" xmlns:topic="http://www.w3.org/2005/Atom">
        <channel>
          <title>Mixed categories</title>
          <item>
            <title>First</title>
            <description><![CDATA[<category>Embedded</category>]]></description>
            <extension><category>Nested</category></extension>
            <category term="ignored">RSS text</category>
            <topic:category term="Atom term"/>
            <category xmlns="urn:other">Foreign text</category>
          </item>
        </channel>
      </rss>
    XML
    feed = SimpleRSS.parse(source, array_tags: [:category])

    assert_equal ["RSS text", "Atom term"], feed.first.category
  end

  def test_rss_namespaces_and_empty_category_behavior_are_preserved
    source = <<~XML
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/">
        <channel><title>RSS 1.0</title></channel>
        <item><title>First</title><category>Ruby</category><category></category></item>
        <item><title>Second</title><category/></item>
      </rdf:RDF>
    XML
    feed = SimpleRSS.parse(source, array_tags: [:category])

    assert_equal ["Ruby", ""], feed.first.category
    assert_nil feed[1].category
    assert_equal "", SimpleRSS.parse(source)[1].category
  end

  def test_namespace_declarations_in_comments_do_not_override_the_feed
    source = <<~XML
      <!-- <feed xmlns="urn:other"> -->
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Actual feed</title>
        <entry><title>First</title><category term="actual"/></entry>
      </feed>
    XML

    assert_equal "actual", SimpleRSS.parse(source).first.category
  end

  def test_rss_channel_namespaces_do_not_apply_to_sibling_rdf_items
    source = <<~XML
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/">
        <channel xmlns:topic="http://www.w3.org/2005/Atom"><title>RSS</title></channel>
        <item><title>First</title><topic:category term="out-of-scope"/><category>RSS text</category></item>
      </rdf:RDF>
    XML

    assert_equal ["RSS text"], SimpleRSS.parse(source, array_tags: [:category]).first.category
  end

  private

  def parse_entry(content, options = {})
    source = <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Categories</title>
        <entry><title>Entry</title>#{content}</entry>
      </feed>
    XML
    SimpleRSS.parse(source, options)
  end
end
