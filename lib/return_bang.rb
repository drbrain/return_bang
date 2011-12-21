begin
  require 'continuation'
rescue LoadError
  # in 1.8 it's built-in
end

##
# ReturnBang is allows you to perform non-local exits from your methods.  One
# potential use of this is in a web framework so that a framework-provided
# utility methods can jump directly back to the request loop.
#
# return_here is used to designate where execution should be resumed.  Return
# points may be arbitrarily nested.  #return! resumes at the previous resume
# point, #return_to returns to a named return point.
#
# require 'return_bang' gives you a module you may include only in your
# application or library code.  require 'return_bang/everywhere' includes
# ReturnBang in Object, so it is only recommended for application code use.
#
# Example:
#
#   include ReturnBang
#
#   def framework_loop
#     loop do
#       # setup code
#
#       return_here do
#         user_code
#       end
#
#       # resume execution here
#     end
#   end
#
#   def render_error_and_return message
#     # generate error
#
#     return!
#   end
#
#   def user_code
#     user_utility_method
#     # these lines never reached
#     # ...
#   end
#
#   def user_utility_method
#     render_error_and_return "blah" if some_condition
#     # these lines never reached
#     # ...
#   end

module ReturnBang

  VERSION = '1.0'

  ##
  # Raised when attempting to return! when you haven't registered a location
  # to return to, or are trying to return to a named point that wasn't
  # registered.

  class NonLocalJumpError < StandardError
  end

  def _return_bang_names # :nodoc:
    Thread.current[:return_bang_names] ||= {}
  end

  if {}.respond_to? :key then # 1.9
    def _return_bang_pop # :nodoc:
      return_point = _return_bang_stack.pop

      _return_bang_names.delete _return_bang_names.key _return_bang_stack.length

      return_point
    end
  else # 1.8
    def _return_bang_pop # :nodoc:
      return_point = _return_bang_stack.pop
      value = _return_bang_stack.length

      _return_bang_names.delete _return_bang_names.index value

      return_point
    end
  end

  def _return_bang_stack # :nodoc:
    Thread.current[:return_bang_stack] ||= []
  end

  ##
  # Returns to the last return point in the stack.  If no return points have
  # been registered a NonLocalJumpError is raised.  +value+ is returned at the
  # registered return point.

  def return! value = nil
    raise NonLocalJumpError, 'nowhere to return to' if
      _return_bang_stack.empty?

    _return_bang_pop.call value
  end

  ##
  # Registers a return point to jump back to.  If a +name+ is given return_to
  # can jump here.

  def return_here name = nil
    raise ArgumentError, "#{name} is already registered as a return point" if
      _return_bang_names.include? name

    value = callcc do |cc|
      _return_bang_names[name] = _return_bang_stack.length if name
      _return_bang_stack.push cc

      begin
        yield
      ensure
        _return_bang_pop
      end
    end

    # here is where the magic happens
    unwind_to = Thread.current[:unwind_to]

    return! value if unwind_to and _return_bang_stack.length > unwind_to

    return value
  end

  ##
  # Returns to the return point +name+.  +value+ is returned at the registered
  # return point.

  def return_to name, value = nil
    unwind_to = _return_bang_names.delete name

    raise NonLocalJumpError, "return point :nonexistent was not set" unless
      unwind_to

    Thread.current[:unwind_to] = unwind_to

    return! value
  end

end

