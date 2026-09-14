module ReplaceMethod
  def with_replaced_method(object, name, replacement)
    own_method = object.singleton_methods(false).include?(name)
    original = object.method(name)
    object.define_singleton_method(name) { |*arguments, **keywords, &block| replacement.call(*arguments, **keywords, &block) }
    yield
  ensure
    if own_method
      object.define_singleton_method(name, original)
    else
      object.singleton_class.remove_method(name)
    end
  end
end
