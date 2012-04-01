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
    assert_nil Thread.current[:current_exception]
  end

  def test__make_exception
    e = _make_exception []

    assert_instance_of RuntimeError, e
  end

  def test__make_exception_class
    e = _make_exception [StandardError]

    assert_instance_of StandardError, e
  end

  def test__make_exception_class_message
    e = _make_exception [StandardError, 'hello']

    assert_instance_of StandardError, e

    assert_equal 'hello', e.message
  end

  def test__make_exception_current_exception
    expected = ArgumentError.new
    Thread.current[:current_exception] = expected

    e = _make_exception []

    assert_same expected, e
  ensure
    Thread.current[:current_exception] = nil
  end

  def test__make_exception_message
    e = _make_exception %w[hello]

    assert_instance_of RuntimeError, e
    assert_equal 'hello', e.message
  end

  def test__make_exception_non_Exception
    e = assert_raises TypeError do
      _make_exception [String]
    end

    assert_equal 'exception class/object expected (not String)', e.message
  end

  def test_ensure_bang
    ensured = false

    return_here do
      ensure! do
        ensured = true
      end
    end

    assert ensured, 'ensured was not executed'
  end

  def test_ensure_bang_multiple
    ensured = []

    return_here do
      ensure! do
        ensured << 1
      end
      ensure! do
        ensured << 2
      end
    end

    assert_equal [1, 2], ensured
  end

  def test_ensure_bang_multiple_return
    ensured = []

    return_here do
      ensure! do
        ensured << 1
      end
      ensure! do
        ensured << 2
      end

      return!
    end

    assert_equal [1, 2], ensured
  end

  def test_ensure_bang_nest
    ensured = []

    return_here do
      ensure! do
        ensured << 2
      end
      return_here do
        ensure! do
          ensured << 1
        end
      end
    end

    assert_equal [1, 2], ensured
  end

  def test_ensure_bang_nest_raise
    ensured = []

    assert_raises RuntimeError do
      return_here do
        ensure! do
          ensured << 2
        end
        return_here do
          ensure! do
            ensured << 1
          end

          raise!
        end
      end
    end

    assert_equal [1, 2], ensured
  end

  def test_ensure_bang_raise_after
    ensured = false

    assert_raises RuntimeError do
      return_here do
        ensure! do
          ensured = true
        end

        refute ensured, 'ensure! executed too soon'

        raise!
      end
    end

    assert ensured, 'ensure! not executed'
  end

  def test_ensure_bang_raise_before
    ensured = false

    assert_raises RuntimeError do
      return_here do
        raise!

        ensure! do
          ensured = true
        end
      end
    end

    refute ensured, 'ensure! must not be executed'
  end

  def test_ensure_bang_raise_in_ensure
    ensured = []

    assert_raises RuntimeError do
      return_here do
        ensure! do
          ensured << 2
        end

        return_here do
          ensure! do
            ensured << 1
            raise!
          end
        end
      end
    end

    assert_equal [1, 2], ensured
  end

  def test_raise_bang
    e = assert_raises RuntimeError do
      return_here do
        raise! 'hello'
      end
    end

    assert_equal 'hello', e.message
  end

  def test_raise_bang_ignore_rescue
    assert_raises RuntimeError do
      return_here do
        begin
          raise! 'hello'
        rescue
          flunk 'must not execute rescue body'
        end
      end
    end
  end

  def test_raise_bang_re_raise
    rescues = []

    assert_raises ArgumentError do
      return_here do
        rescue! do
          rescues << 2
        end

        return_here do
          rescue! do
            rescues << 1

            raise!
          end

          raise! ArgumentError, 'hello'
        end
      end
    end

    assert_equal [1, 2], rescues
  end

  def test_rescue_bang
    rescued = false

    assert_raises RuntimeError do
      return_here do
        rescue! do
          rescued = true
        end

        raise! 'hello'
      end
    end

    assert rescued, 'rescue not executed'
  end

  def test_rescue_bang_default
    rescued = false

    assert_raises Exception do
      return_here do
        rescue! do
          rescued = true
        end

        raise! Exception 
      end
    end

    refute rescued, 'rescue must default to StandardError'
  end

  def test_rescue_bang_exceptions
    rescued = false
    ensured = true

    return_here do
      rescue! do
        rescued = true
      end

      ensure! do
        ensured = true
      end

      return!
    end

    refute rescued, 'rescue! must not execute'
    assert ensured, 'ensure! must execute'
  end

  def test_rescue_bang_multiple
    rescued = false

    assert_raises TypeError do
      return_here do
        rescue! ArgumentError, TypeError do
          rescued = true
        end

        raise! TypeError
      end
    end

    assert rescued, 'rescue not executed'
  end

  def test_rescue_bang_type
    rescued = false

    assert_raises StandardError do
      return_here do
        rescue! StandardError do
          rescued = true
        end

        rescue! RuntimeError do
          flunk 'wrong rescue! executed'
        end

        raise! StandardError
      end
    end

    assert rescued, 'StandardError exception not rescued'
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

