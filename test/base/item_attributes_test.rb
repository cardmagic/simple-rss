require "test_helper"

class ItemAttributesTest < Test::Unit::TestCase
  def setup
    # Add item/entry attribute tags before parsing
    SimpleRSS.item_tags << :"entry#custom:id"
    SimpleRSS.item_tags << :"item#data-id"

    @atom = SimpleRSS.parse open(File.dirname(__FILE__) + "/../data/atom_with_entry_attrs.xml")
    @rss20 = SimpleRSS.parse open(File.dirname(__FILE__) + "/../data/rss20_with_item_attrs.xml")
  end

  def teardown
    # Clean up added tags
    SimpleRSS.item_tags.delete(:"entry#custom:id")
    SimpleRSS.item_tags.delete(:"item#data-id")
  end

  def test_atom_entry_attribute
    assert_equal "12345", @atom.entries.first[:entry_custom_id]
  end

  def test_rss20_item_attribute
    assert_equal "67890", @rss20.items.first[:"item_data-id"]
  end
end
