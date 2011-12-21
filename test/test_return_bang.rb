require 'minitest/autorun'
require 'return_bang'

class TestReturnBang < MiniTest::Unit::TestCase

  include ReturnBang

  def setup
    @after_a = false
    @after_e = false
  end

  def teardown
    assert_empty _return_bang_stack
    assert_empty _return_bang_names
  end

  def test_return_bang_no_return_here
    e = assert_raises NonLocalJumpError do
      return!
    end

    assert_equal 'nowhere to return to', e.message
  end

  def test_return_here
    result = return_here do a end

    refute @after_a, 'return! did not skip after_a'

    assert_equal 42, result
  end

  def test_return_here_name
    result = return_here :name do d end

    refute @after_e, 'return_to did not skip after_e'

    assert_equal 43, result
  end

  def test_return_here_name_no_return_bang
    result = return_here :name do c end

    assert_equal 24, result
  end

  def test_return_here_nest
    result = return_here do
      return_here do
        a
      end
    end

    refute @after_a, 'return! did not skip after_a'

    assert_equal 42, result
  end

  def test_return_here_no_return_bang
    result = return_here do c end

    assert_equal 24, result
  end

  def test_return_to_no_return_here
    e = assert_raises NonLocalJumpError do
      return_to :nonexistent
    end

    assert_equal 'return point :nonexistent was not set', e.message
  end

  def a() b; @after_a = true end
  def b() return! 42 end

  def c() 24 end

  def d() return_here do e end; @after_e = true end
  def e() return_to :name, 43 end

end

