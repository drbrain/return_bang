require 'continuation'

##
# ReturnBang is allows you to perform non-local exits from your methods.  One
# potential use of this is in a web framework so that a framework-provided
# utility methods can jump directly back to the request loop.
#
# Since providing just non-local exits is insufficient for modern Ruby
# development, full exception handling support is also provided via #raise!,
# #rescue! and #ensure!.  This exception handling support completely bypasses
# Ruby's strict <tt>begin; rescue; ensure; return</tt> handling.
#
# require 'return_bang' gives you a module you may include only in your
# application or library code.  require 'return_bang/everywhere' includes
# ReturnBang in Object, so it is only recommended for application code use.
#
# == Methods
#
# return_here is used to designate where execution should be resumed.  Return
# points may be arbitrarily nested.  #return! resumes at the previous resume
# point, #return_to returns to a named return point.
#
# #raise! is used to indicate an exceptional situation has occurred and you
# would like to skip the rest of the execution.
#
# #rescue! is used to rescue exceptions if you have a way to handle them.
#
# #ensure! is used when you need to perform cleanup where an exceptional
# situation may occur.
#
# == Example
#
#   include ReturnBang
#
#   def framework_loop
#     loop do
#       return_here do
#         # setup this request
#
#         ensure! do
#           # clean up this request
#         end
#
#         rescue! FrameworkError do
#           # display framework error
#         end
#
#         rescue! do
#           # display application error
#         end
#
#         user_code
#       end
#     end
#   end
#
#   def user_code
#     user_utility_method
#
#     other_condition = some_more code
#
#     return! if other_condition
#
#     # rest of user method
#   end
#
#   def user_utility_method
#     raise! "there was an error" if some_condition
#
#     # rest of utility method
#   end

module ReturnBang

  VERSION = '1.0'

  ##
  # Raised when attempting to return! when you haven't registered a location
  # to return to, or are trying to return to a named point that wasn't
  # registered.

  class NonLocalJumpError < StandardError
  end

  def _make_exception args # :nodoc:
    case args.length
    when 0 then
      if exception = Thread.current[:current_exception] then
        exception
      else
        RuntimeError.new
      end
    when 1 then # exception or string
      arg = args.first

      case arg = args.first
      when Class then
        unless Exception >= arg then
          raise TypeError,
                "exception class/object expected (not #{arg.inspect})"
        end
        arg.new
      else
        RuntimeError.new arg
      end
    when 2 then # exception, string
      klass, message = args
      klass.new message
    else
      raise ArgumentError, 'too many arguments to raise!'
    end
  end

  ##
  # Executes the ensure blocks in +frames+ in the correct order.

  def _return_bang_cleanup frames # :nodoc:
    chunked = frames.chunk do |type,|
      type
    end

    chunked.reverse_each do |type, chunk_frames|
      case type
      when :ensure then
        chunk_frames.each do |_, block|
          block.call
        end
      when :rescue then
        if exception = Thread.current[:current_exception] then
          frame = chunk_frames.find do |_, block, objects|
            objects.any? do |object|
              object === exception
            end
          end

          next unless frame

          # rebuild stack since we've got a handler for the exception.
          unexecuted = frames[0, frames.index(frame) - 1]
          _return_bang_stack.concat unexecuted if unexecuted

          _, handler, = frame
          handler.call exception

          return # the exception was handled, don't continue up the stack
        end
      when :return then
        # ignore
      else
        raise "[bug] unknown return_bang frame type #{type}"
      end
    end
  end

  def _return_bang_names # :nodoc:
    Thread.current[:return_bang_names] ||= {}
  end

  def _return_bang_pop # :nodoc:
    frame = _return_bang_stack.pop

    _return_bang_names.delete _return_bang_names.key _return_bang_stack.length

    frame
  end

  def _return_bang_stack # :nodoc:
    Thread.current[:return_bang_stack] ||= []
  end

  ##
  # Unwinds the stack to +continuation+ including trimming the stack above the
  # continuation, removing named return_heres that can't be reached and
  # executing any ensures in the trimmed stack.

  def _return_bang_unwind_to continuation # :nodoc:
    found = false

    frames = _return_bang_stack.select do |_, block|
      found || found = block == continuation
    end

    start = _return_bang_stack.length - frames.length

    _return_bang_stack.slice! start, frames.length

    frames.each_index do |index|
      offset = start + index

      _return_bang_names.delete _return_bang_names.key offset
    end

    _return_bang_cleanup frames
  end

  ##
  # Adds an ensure block that will be run when exiting this return_here block.
  #
  # ensure! blocks run in the order defined and can be added at any time.  If
  # an exception is raised before an ensure! block is encountered, that block
  # will not be executed.
  #
  # Example:
  #
  #   return_here do
  #     ensure! do
  #       # this ensure! will be executed
  #     end
  #
  #     raise! "uh-oh!"
  #
  #     ensure! do
  #       # this ensure! will not be executed
  #     end
  #   end

  def ensure! &block
    _return_bang_stack.push [:ensure, block]
  end

  ##
  # Raises an exception like Kernel#raise.
  #
  # ensure! blocks and rescue! exception handlers will be run as the exception
  # is propagated up the stack.

  def raise! *args
    Thread.current[:current_exception] = _make_exception args

    type, = _return_bang_stack.first

    _, final = _return_bang_stack.shift if type == :return

    frames = _return_bang_stack.dup

    _return_bang_stack.clear

    _return_bang_cleanup frames

    final.call if final
  end

  ##
  # Rescues +exceptions+ raised by raise! and yields the exception caught to
  # the block given.
  #
  # If no exceptions are given, StandardError is rescued (like the rescue
  # keyword).
  #
  # Example:
  #
  #   return_here do
  #     rescue! do |e|
  #       puts "handled exception #{e.class}: #{e}"
  #     end
  #
  #     raise! "raising an exception"
  #   end

  def rescue! *exceptions, &block
    exceptions = [StandardError] if exceptions.empty?

    _return_bang_stack.push [:rescue, block, exceptions]
  end

  ##
  # Returns to the last return point in the stack.  If no return points have
  # been registered a NonLocalJumpError is raised.  +value+ is returned at the
  # registered return point.

  def return! value = nil
    raise NonLocalJumpError, 'nowhere to return to' if
      _return_bang_stack.empty?

    _, continuation, = _return_bang_stack.reverse.find do |type,|
      type == :return
    end

    _return_bang_unwind_to continuation

    continuation.call value
  end

  ##
  # Registers a return point to jump back to.  If a +name+ is given return_to
  # can jump here.

  def return_here name = nil
    raise ArgumentError, "#{name} is already registered as a return point" if
      _return_bang_names.include? name

    value = callcc do |cc|
      _return_bang_names[name] = _return_bang_stack.length if name
      _return_bang_stack.push [:return, cc]

      begin
        yield
      ensure
        _return_bang_unwind_to cc
      end
    end

    if exception = Thread.current[:current_exception] then
      Thread.current[:current_exception] = nil

      raise exception
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

