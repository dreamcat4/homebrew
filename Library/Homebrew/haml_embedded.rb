# Vendored from Haml: http://github.com/nex3/haml
#
# Copyright (c) 2006-2009 Hampton Catlin, Nathan Weizenbaum, and Chris Eppstein
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# haml/helpers.rb:
# if defined?(ActionView)
#   require 'haml/helpers/action_view_mods'
#   require 'haml/helpers/action_view_extensions'
# end

module Haml
  # This module contains various helpful methods to make it easier to do various tasks.
  # {Haml::Helpers} is automatically included in the context
  # that a Haml template is parsed in, so all these methods are at your
  # disposal from within the template.
  module Helpers
    # An object that raises an error when \{#to\_s} is called.
    # It's used to raise an error when the return value of a helper is used
    # when it shouldn't be.
    class ErrorReturn
      # @param message [String] The error message to raise when \{#to\_s} is called
      def initialize(method)
        @message = <<MESSAGE
#{method} outputs directly to the Haml template.
Disregard its return value and use the - operator,
or use capture_haml to get the value as a String.
MESSAGE
      end

      # Raises an error.
      #
      # @raise [Haml::Error] The error
      def to_s
        raise Haml::Error.new(@message)
      rescue Haml::Error => e
        e.backtrace.shift

        # If the ErrorReturn is used directly in the template,
        # we don't want Haml's stuff to get into the backtrace,
        # so we get rid of the format_script line.
        #
        # We also have to subtract one from the Haml line number
        # since the value is passed to format_script the line after
        # it's actually used.
        if e.backtrace.first =~ /^\(eval\):\d+:in `format_script/
          e.backtrace.shift
          e.backtrace.first.gsub!(/^\(haml\):(\d+)/) {|s| "(haml):#{$1.to_i - 1}"}
        end
        raise e
      end

      # @return [String] A human-readable string representation
      def inspect
        "Haml::Helpers::ErrorReturn(#{@message.inspect})"
      end
    end

    self.extend self

    @@action_view_defined = defined?(ActionView)
    @@force_no_action_view = false

    # @return [Boolean] Whether or not ActionView is loaded
    def self.action_view?
      @@action_view_defined
    end

    # Note: this does **not** need to be called when using Haml helpers
    # normally in Rails.
    #
    # Initializes the current object as though it were in the same context
    # as a normal ActionView instance using Haml.
    # This is useful if you want to use the helpers in a context
    # other than the normal setup with ActionView.
    # For example:
    #
    #     context = Object.new
    #     class << context
    #       include Haml::Helpers
    #     end
    #     context.init_haml_helpers
    #     context.haml_tag :p, "Stuff"
    #
    def init_haml_helpers
      @haml_buffer = Haml::Buffer.new(@haml_buffer, Haml::Engine.new('').send(:options_for_buffer))
      nil
    end

    # Runs a block of code in a non-Haml context
    # (i.e. \{#is\_haml?} will return false).
    #
    # This is mainly useful for rendering sub-templates such as partials in a non-Haml language,
    # particularly where helpers may behave differently when run from Haml.
    #
    # Note that this is automatically applied to Rails partials.
    #
    # @yield A block which won't register as Haml
    def non_haml
      was_active = @haml_buffer.active?
      @haml_buffer.active = false
      yield
    ensure
      @haml_buffer.active = was_active
    end

    # Uses \{#preserve} to convert any newlines inside whitespace-sensitive tags
    # into the HTML entities for endlines.
    #
    # @param tags [Array<String>] Tags that should have newlines escaped
    #
    # @overload find_and_preserve(input, tags = haml_buffer.options[:preserve])
    #   Escapes newlines within a string.
    #
    #   @param input [String] The string within which to escape newlines
    # @overload find_and_preserve(tags = haml_buffer.options[:preserve])
    #   Escapes newlines within a block of Haml code.
    #
    #   @yield The block within which to escape newlines
    def find_and_preserve(input = nil, tags = haml_buffer.options[:preserve], &block)
      return find_and_preserve(capture_haml(&block), input || tags) if block
      input.to_s.gsub(/<(#{tags.map(&Regexp.method(:escape)).join('|')})([^>]*)>(.*?)(<\/\1>)/im) do
        "<#{$1}#{$2}>#{preserve($3)}</#{$1}>"
      end
    end

    # Takes any string, finds all the newlines, and converts them to
    # HTML entities so they'll render correctly in
    # whitespace-sensitive tags without screwing up the indentation.
    #
    # @overload perserve(input)
    #   Escapes newlines within a string.
    #
    #   @param input [String] The string within which to escape all newlines
    # @overload perserve
    #   Escapes newlines within a block of Haml code.
    #
    #   @yield The block within which to escape newlines
    def preserve(input = nil, &block)
      return preserve(capture_haml(&block)) if block
      input.to_s.chomp("\n").gsub(/\n/, '&#x000A;').gsub(/\r/, '')
    end
    alias_method :flatten, :preserve

    # Takes an `Enumerable` object and a block
    # and iterates over the enum,
    # yielding each element to a Haml block
    # and putting the result into `<li>` elements.
    # This creates a list of the results of the block.
    # For example:
    #
    #     = list_of([['hello'], ['yall']]) do |i|
    #       = i[0]
    #
    # Produces:
    #
    #     <li>hello</li>
    #     <li>yall</li>
    #
    # And
    #
    #     = list_of({:title => 'All the stuff', :description => 'A book about all the stuff.'}) do |key, val|
    #       %h3= key.humanize
    #       %p= val
    #
    # Produces:
    #
    #     <li>
    #       <h3>Title</h3>
    #       <p>All the stuff</p>
    #     </li>
    #     <li>
    #       <h3>Description</h3>
    #       <p>A book about all the stuff.</p>
    #     </li>
    #
    # @param enum [Enumerable] The list of objects to iterate over
    # @yield [item] A block which contains Haml code that goes within list items
    # @yieldparam item An element of `enum`
    def list_of(enum, &block)
      to_return = enum.collect do |i|
        result = capture_haml(i, &block)

        if result.count("\n") > 1
          result.gsub!("\n", "\n  ")
          result = "\n  #{result.strip}\n"
        else
          result.strip!
        end

        "<li>#{result}</li>"
      end
      to_return.join("\n")
    end

    # Returns a hash containing default assignments for the `xmlns`, `lang`, and `xml:lang`
    # attributes of the `html` HTML element.
    # For example,
    #
    #     %html{html_attrs}
    #
    # becomes
    #
    #     <html xmlns='http://www.w3.org/1999/xhtml' xml:lang='en-US' lang='en-US'>
    #
    # @param lang [String] The value of `xml:lang` and `lang`
    # @return [{#to_s => String}] The attribute hash
    def html_attrs(lang = 'en-US')
      {:xmlns => "http://www.w3.org/1999/xhtml", 'xml:lang' => lang, :lang => lang}
    end

    # Increments the number of tabs the buffer automatically adds
    # to the lines of the template.
    # For example:
    #
    #     %h1 foo
    #     - tab_up
    #     %p bar
    #     - tab_down
    #     %strong baz
    #
    # Produces:
    #
    #     <h1>foo</h1>
    #       <p>bar</p>
    #     <strong>baz</strong>
    #
    # @param i [Fixnum] The number of tabs by which to increase the indentation
    # @see #tab_down
    def tab_up(i = 1)
      haml_buffer.tabulation += i
    end

    # Decrements the number of tabs the buffer automatically adds
    # to the lines of the template.
    #
    # @param i [Fixnum] The number of tabs by which to decrease the indentation
    # @see #tab_up
    def tab_down(i = 1)
      haml_buffer.tabulation -= i
    end

    # Surrounds a block of Haml code with strings,
    # with no whitespace in between.
    # For example:
    #
    #     = surround '(', ')' do
    #       %a{:href => "food"} chicken
    #
    # Produces:
    #
    #     (<a href='food'>chicken</a>)
    #
    # and
    #
    #     = surround '*' do
    #       %strong angry
    #
    # Produces:
    #
    #     *<strong>angry</strong>*
    #
    # @param front [String] The string to add before the Haml
    # @param back [String] The string to add after the Haml
    # @yield A block of Haml to surround
    def surround(front, back = front, &block)
      output = capture_haml(&block)

      "#{front}#{output.chomp}#{back}\n"
    end

    # Prepends a string to the beginning of a Haml block,
    # with no whitespace between.
    # For example:
    #
    #     = precede '*' do
    #       %span.small Not really
    #
    # Produces:
    #
    #     *<span class='small'>Not really</span>
    #
    # @param str [String] The string to add before the Haml
    # @yield A block of Haml to prepend to
    def precede(str, &block)
      "#{str}#{capture_haml(&block).chomp}\n"
    end

    # Appends a string to the end of a Haml block,
    # with no whitespace between.
    # For example:
    #
    #     click
    #     = succeed '.' do
    #       %a{:href=>"thing"} here
    #
    # Produces:
    #
    #     click
    #     <a href='thing'>here</a>.
    #
    # @param str [String] The string to add after the Haml
    # @yield A block of Haml to append to
    def succeed(str, &block)
      "#{capture_haml(&block).chomp}#{str}\n"
    end

    # Captures the result of a block of Haml code,
    # gets rid of the excess indentation,
    # and returns it as a string.
    # For example, after the following,
    #
    #     .foo
    #       - foo = capture_haml(13) do |a|
    #         %p= a
    #
    # the local variable `foo` would be assigned to `"<p>13</p>\n"`.
    #
    # @param args [Array] Arguments to pass into the block
    # @yield [args] A block of Haml code that will be converted to a string
    # @yieldparam args [Array] `args`
    def capture_haml(*args, &block)
      buffer = eval('_hamlout', block.binding) rescue haml_buffer
      with_haml_buffer(buffer) do
        position = haml_buffer.buffer.length

        haml_buffer.capture_position = position
        block.call(*args)

        captured = haml_buffer.buffer.slice!(position..-1).split(/^/)

        min_tabs = nil
        captured.each do |line|
          tabs = line.index(/[^ ]/) || line.length
          min_tabs ||= tabs
          min_tabs = min_tabs > tabs ? tabs : min_tabs
        end

        captured.map do |line|
          line[min_tabs..-1]
        end.join
      end
    ensure
      haml_buffer.capture_position = nil
    end

    # Outputs text directly to the Haml buffer, with the proper indentation.
    #
    # @param text [#to_s] The text to output
    def haml_concat(text = "")
      unless haml_buffer.options[:ugly] || haml_indent == 0
        haml_buffer.buffer << haml_indent <<
          text.to_s.gsub("\n", "\n" + haml_indent) << "\n"
      else
        haml_buffer.buffer << text.to_s << "\n"
      end
      ErrorReturn.new("haml_concat")
    end

    # @return [String] The indentation string for the current line
    def haml_indent
      '  ' * haml_buffer.tabulation
    end

    # Creates an HTML tag with the given name and optionally text and attributes.
    # Can take a block that will run between the opening and closing tags.
    # If the block is a Haml block or outputs text using \{#haml\_concat},
    # the text will be properly indented.
    #
    # `name` can be a string using the standard Haml class/id shorthand
    # (e.g. "span#foo.bar", "#foo").
    # Just like standard Haml tags, these class and id values
    # will be merged with manually-specified attributes.
    #
    # `flags` is a list of symbol flags
    # like those that can be put at the end of a Haml tag
    # (`:/`, `:<`, and `:>`).
    # Currently, only `:/` and `:<` are supported.
    #
    # `haml_tag` outputs directly to the buffer;
    # its return value should not be used.
    # If you need to get the results as a string,
    # use \{#capture\_haml\}.
    #
    # For example,
    #
    #     haml_tag :table do
    #       haml_tag :tr do
    #         haml_tag 'td.cell' do
    #           haml_tag :strong, "strong!"
    #           haml_concat "data"
    #         end
    #         haml_tag :td do
    #           haml_concat "more_data"
    #         end
    #       end
    #     end
    #
    # outputs
    #
    #     <table>
    #       <tr>
    #         <td class='cell'>
    #           <strong>
    #             strong!
    #           </strong>
    #           data
    #         </td>
    #         <td>
    #           more_data
    #         </td>
    #       </tr>
    #     </table>
    #
    # @param name [#to_s] The name of the tag
    # @param flags [Array<Symbol>] Haml end-of-tag flags
    #
    # @overload haml_tag(name, *flags, attributes = {})
    #   @yield The block of Haml code within the tag
    # @overload haml_tag(name, text, *flags, attributes = {})
    #   @param text [#to_s] The text within the tag
    def haml_tag(name, *rest, &block)
      ret = ErrorReturn.new("haml_tag")

      text = rest.shift.to_s unless [Symbol, Hash, NilClass].any? {|t| rest.first.is_a? t}
      flags = []
      flags << rest.shift while rest.first.is_a? Symbol
      name, attrs = merge_name_and_attributes(name.to_s, rest.shift || {})

      attributes = Haml::Precompiler.build_attributes(haml_buffer.html?,
                                                      haml_buffer.options[:attr_wrapper],
                                                      attrs)

      if text.nil? && block.nil? && (haml_buffer.options[:autoclose].include?(name) || flags.include?(:/))
        haml_concat "<#{name}#{attributes} />"
        return ret
      end

      if flags.include?(:/)
        raise Error.new("Self-closing tags can't have content.") if text
        raise Error.new("Illegal nesting: nesting within a self-closing tag is illegal.") if block
      end

      tag = "<#{name}#{attributes}>"
      if block.nil?
        text = text.to_s
        if text.include?("\n")
          haml_concat tag
          tab_up
          haml_concat text
          tab_down
          haml_concat "</#{name}>"
        else
          tag << text << "</#{name}>"
          haml_concat tag
        end
        return ret
      end

      if text
        raise Error.new("Illegal nesting: content can't be both given to haml_tag :#{name} and nested within it.")
      end

      if flags.include?(:<)
        tag << capture_haml(&block).strip << "</#{name}>"
        haml_concat tag
        return ret
      end

      haml_concat tag
      tab_up
      block.call
      tab_down
      haml_concat "</#{name}>"

      ret
    end

    # Characters that need to be escaped to HTML entities from user input
    # @private
    HTML_ESCAPE = { '&'=>'&amp;', '<'=>'&lt;', '>'=>'&gt;', '"'=>'&quot;', "'"=>'&#039;', }

    # Returns a copy of `text` with ampersands, angle brackets and quotes
    # escaped into HTML entities.
    #
    # Note that if ActionView is loaded and XSS protection is enabled
    # (as is the default for Rails 3.0+, and optional for version 2.3.5+),
    # this won't escape text declared as "safe".
    #
    # @param text [String] The string to sanitize
    # @return [String] The sanitized string
    def html_escape(text)
      text.to_s.gsub(/[\"><&]/n) {|s| HTML_ESCAPE[s]}
    end

    # Escapes HTML entities in `text`, but without escaping an ampersand
    # that is already part of an escaped entity.
    #
    # @param text [String] The string to sanitize
    # @return [String] The sanitized string
    def escape_once(text)
      Haml::Util.silence_warnings do
        text.to_s.gsub(/[\"><]|&(?!(?:[a-zA-Z]+|(#\d+));)/n) {|s| HTML_ESCAPE[s]}
      end
    end

    # Returns whether or not the current template is a Haml template.
    #
    # This function, unlike other {Haml::Helpers} functions,
    # also works in other `ActionView` templates,
    # where it will always return false.
    #
    # @return [Boolean] Whether or not the current template is a Haml template
    def is_haml?
      !@haml_buffer.nil? && @haml_buffer.active?
    end

    # Returns whether or not `block` is defined directly in a Haml template.
    #
    # @param block [Proc] A Ruby block
    # @return [Boolean] Whether or not `block` is defined directly in a Haml template
    def block_is_haml?(block)
      eval('_hamlout', block.binding)
      true
    rescue
      false
    end

    private

    # Parses the tag name used for \{#haml\_tag}
    # and merges it with the Ruby attributes hash.
    def merge_name_and_attributes(name, attributes_hash = {})
      # skip merging if no ids or classes found in name
      return name, attributes_hash unless name =~ /^(.+?)?([\.#].*)$/

      return $1 || "div", Buffer.merge_attrs(
        Precompiler.parse_class_and_id($2),
        Haml::Util.map_keys(attributes_hash) {|key| key.to_s})
    end

    # Runs a block of code with the given buffer as the currently active buffer.
    #
    # @param buffer [Haml::Buffer] The Haml buffer to use temporarily
    # @yield A block in which the given buffer should be used
    def with_haml_buffer(buffer)
      @haml_buffer, old_buffer = buffer, @haml_buffer
      old_buffer.active, old_was_active = false, old_buffer.active? if old_buffer
      @haml_buffer.active, was_active = true, @haml_buffer.active?
      yield
    ensure
      @haml_buffer.active = was_active
      old_buffer.active = old_was_active if old_buffer
      @haml_buffer = old_buffer
    end

    # The current {Haml::Buffer} object.
    #
    # @return [Haml::Buffer]
    def haml_buffer
      @haml_buffer
    end

    # Gives a proc the same local `_hamlout` and `_erbout` variables
    # that the current template has.
    #
    # @param proc [#call] The proc to bind
    # @return [Proc] A new proc with the new variables bound
    def haml_bind_proc(&proc)
      _hamlout = haml_buffer
      _erbout = _hamlout.buffer
      proc { |*args| proc.call(*args) }
    end

    # include ActionViewExtensions if self.const_defined? "ActionViewExtensions"
  end
end

class Object
  # Haml overrides various `ActionView` helpers,
  # which call an \{#is\_haml?} method
  # to determine whether or not the current context object
  # is a proper Haml context.
  # Because `ActionView` helpers may be included in non-`ActionView::Base` classes,
  # it's a good idea to define \{#is\_haml?} for all objects.
  def is_haml?
    false
  end
end

# haml/buffer.rb:
module Haml
  # This class is used only internally. It holds the buffer of HTML that
  # is eventually output as the resulting document.
  # It's called from within the precompiled code,
  # and helps reduce the amount of processing done within `instance_eval`ed code.
  class Buffer
    include Haml::Helpers
    include Haml::Util

    # The string that holds the compiled HTML. This is aliased as
    # `_erbout` for compatibility with ERB-specific code.
    #
    # @return [String]
    attr_accessor :buffer

    # The options hash passed in from {Haml::Engine}.
    #
    # @return [{String => Object}]
    # @see Haml::Engine#options_for_buffer
    attr_accessor :options

    # The {Buffer} for the enclosing Haml document.
    # This is set for partials and similar sorts of nested templates.
    # It's `nil` at the top level (see \{#toplevel?}).
    #
    # @return [Buffer]
    attr_accessor :upper

    # nil if there's no capture_haml block running,
    # and the position at which it's beginning the capture if there is one.
    #
    # @return [Fixnum, nil]
    attr_accessor :capture_position

    # @return [Boolean]
    # @see #active?
    attr_writer :active

    # @return [Boolean] Whether or not the format is XHTML
    def xhtml?
      not html?
    end

    # @return [Boolean] Whether or not the format is any flavor of HTML
    def html?
      html4? or html5?
    end

    # @return [Boolean] Whether or not the format is HTML4
    def html4?
      @options[:format] == :html4
    end

    # @return [Boolean] Whether or not the format is HTML5.
    def html5?
      @options[:format] == :html5
    end

    # @return [Boolean] Whether or not this buffer is a top-level template,
    #   as opposed to a nested partial
    def toplevel?
      upper.nil?
    end

    # Whether or not this buffer is currently being used to render a Haml template.
    # Returns `false` if a subtemplate is being rendered,
    # even if it's a subtemplate of this buffer's template.
    #
    # @return [Boolean]
    def active?
      @active
    end

    # @return [Fixnum] The current indentation level of the document
    def tabulation
      @real_tabs + @tabulation
    end

    # Sets the current tabulation of the document.
    #
    # @param val [Fixnum] The new tabulation
    def tabulation=(val)
      val = val - @real_tabs
      @tabulation = val > -1 ? val : 0
    end

    # @param upper [Buffer] The parent buffer
    # @param options [{Symbol => Object}] An options hash.
    #   See {Haml::Engine#options\_for\_buffer}
    def initialize(upper = nil, options = {})
      @active = true
      @upper = upper
      @options = options
      @buffer = ruby1_8? ? "" : "".encode(Encoding.find(options[:encoding]))
      @tabulation = 0

      # The number of tabs that Engine thinks we should have
      # @real_tabs + @tabulation is the number of tabs actually output
      @real_tabs = 0
    end

    # Appends text to the buffer, properly tabulated.
    # Also modifies the document's indentation.
    #
    # @param text [String] The text to append
    # @param tab_change [Fixnum] The number of tabs by which to increase
    #   or decrease the document's indentation
    # @param dont_tab_up [Boolean] If true, don't indent the first line of `text`
    def push_text(text, tab_change, dont_tab_up)
      if @tabulation > 0
        # Have to push every line in by the extra user set tabulation.
        # Don't push lines with just whitespace, though,
        # because that screws up precompiled indentation.
        text.gsub!(/^(?!\s+$)/m, tabs)
        text.sub!(tabs, '') if dont_tab_up
      end

      @buffer << text
      @real_tabs += tab_change
    end

    # Modifies the indentation of the document.
    #
    # @param tab_change [Fixnum] The number of tabs by which to increase
    #   or decrease the document's indentation
    def adjust_tabs(tab_change)
      @real_tabs += tab_change
    end

    Haml::Util.def_static_method(self, :format_script, [:result],
                                 :preserve_script, :in_tag, :preserve_tag, :escape_html,
                                 :nuke_inner_whitespace, :interpolated, :ugly, <<RUBY)
      <% # Escape HTML here so that the safety of the string is preserved in Rails
         result_name = escape_html ? "html_escape(result.to_s)" : "result.to_s" %>
      <% unless ugly %>
        # If we're interpolated,
        # then the custom tabulation is handled in #push_text.
        # The easiest way to avoid it here is to reset @tabulation.
        <% if interpolated %>
          old_tabulation = @tabulation
          @tabulation = 0
        <% end %>

        tabulation = @real_tabs
        result = <%= result_name %>.<% if nuke_inner_whitespace %>strip<% else %>rstrip<% end %>
      <% else %>
        result = <%= result_name %><% if nuke_inner_whitespace %>.strip<% end %>
      <% end %>

      <% if preserve_tag %>
        result = Haml::Helpers.preserve(result)
      <% elsif preserve_script %>
        result = Haml::Helpers.find_and_preserve(result, options[:preserve])
      <% end %>

      <% if ugly %>
        return result
      <% else %>

        has_newline = result.include?("\\n") 
        <% if in_tag && !nuke_inner_whitespace %>
          <% unless preserve_tag %> if !has_newline <% end %>
          @real_tabs -= 1
          <% if interpolated %> @tabulation = old_tabulation <% end %>
          return result
          <% unless preserve_tag %> end <% end %>
        <% end %>

        # Precompiled tabulation may be wrong
        <% if !interpolated && !in_tag %>
          result = tabs + result if @tabulation > 0
        <% end %>

        if has_newline
          result = result.gsub "\\n", "\\n" + tabs(tabulation)

          # Add tabulation if it wasn't precompiled
          <% if in_tag && !nuke_inner_whitespace %> result = tabs(tabulation) + result <% end %>
        end

        <% if in_tag && !nuke_inner_whitespace %>
          result = "\\n\#{result}\\n\#{tabs(tabulation-1)}"
          @real_tabs -= 1
        <% end %>
        <% if interpolated %> @tabulation = old_tabulation <% end %>
        result
      <% end %>
RUBY

    # Takes the various information about the opening tag for an element,
    # formats it, and appends it to the buffer.
    def open_tag(name, self_closing, try_one_line, preserve_tag, escape_html, class_id,
                 nuke_outer_whitespace, nuke_inner_whitespace, obj_ref, content, *attributes_hashes)
      tabulation = @real_tabs

      attributes = class_id
      attributes_hashes.each do |old|
        self.class.merge_attrs(attributes, to_hash(old.map {|k, v| [k.to_s, v]}))
      end
      self.class.merge_attrs(attributes, parse_object_ref(obj_ref)) if obj_ref

      if self_closing && xhtml?
        str = " />" + (nuke_outer_whitespace ? "" : "\n")
      else
        str = ">" + ((if self_closing && html?
                        nuke_outer_whitespace
                      else
                        try_one_line || preserve_tag || nuke_inner_whitespace
                      end) ? "" : "\n")
      end

      attributes = Precompiler.build_attributes(html?, @options[:attr_wrapper], attributes)
      @buffer << "#{nuke_outer_whitespace || @options[:ugly] ? '' : tabs(tabulation)}<#{name}#{attributes}#{str}"

      if content
        @buffer << "#{content}</#{name}>" << (nuke_outer_whitespace ? "" : "\n")
        return
      end

      @real_tabs += 1 unless self_closing || nuke_inner_whitespace
    end

    # Remove the whitespace from the right side of the buffer string.
    # Doesn't do anything if we're at the beginning of a capture_haml block.
    def rstrip!
      if capture_position.nil?
        buffer.rstrip!
        return
      end

      buffer << buffer.slice!(capture_position..-1).rstrip
    end

    # Merges two attribute hashes.
    # This is the same as `to.merge!(from)`,
    # except that it merges id and class attributes.
    #
    # ids are concatenated with `"_"`,
    # and classes are concatenated with `" "`.
    #
    # Destructively modifies both `to` and `from`.
    #
    # @param to [{String => String}] The attribute hash to merge into
    # @param from [{String => #to_s}] The attribute hash to merge from
    # @return [{String => String}] `to`, after being merged
    def self.merge_attrs(to, from)
      if to['id'] && from['id']
        to['id'] << '_' << from.delete('id').to_s
      elsif to['id'] || from['id']
        from['id'] ||= to['id']
      end

      if to['class'] && from['class']
        # Make sure we don't duplicate class names
        from['class'] = (from['class'].to_s.split(' ') | to['class'].split(' ')).sort.join(' ')
      elsif to['class'] || from['class']
        from['class'] ||= to['class']
      end

      to.merge!(from)
    end

    private

    @@tab_cache = {}
    # Gets `count` tabs. Mostly for internal use.
    def tabs(count = 0)
      tabs = [count + @tabulation, 0].max
      @@tab_cache[tabs] ||= '  ' * tabs
    end

    # Takes an array of objects and uses the class and id of the first
    # one to create an attributes hash.
    # The second object, if present, is used as a prefix,
    # just like you can do with `dom_id()` and `dom_class()` in Rails
    def parse_object_ref(ref)
      prefix = ref[1]
      ref = ref[0]
      # Let's make sure the value isn't nil. If it is, return the default Hash.
      return {} if ref.nil?
      class_name =
        if ref.respond_to?(:haml_object_ref)
          ref.haml_object_ref
        else
          underscore(ref.class)
        end
      id = "#{class_name}_#{ref.id || 'new'}"
      if prefix
        class_name = "#{ prefix }_#{ class_name}"
        id = "#{ prefix }_#{ id }"
      end

      {'id' => id, 'class' => class_name}
    end

    # Changes a word from camel case to underscores.
    # Based on the method of the same name in Rails' Inflector,
    # but copied here so it'll run properly without Rails.
    def underscore(camel_cased_word)
      camel_cased_word.to_s.gsub(/::/, '_').
        gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
        gsub(/([a-z\d])([A-Z])/,'\1_\2').
        tr("-", "_").
        downcase
    end
  end
end

# haml/shared.rb:
require 'strscan'

module Haml
  # This module contains functionality that's shared between Haml and Sass.
  module Shared
    extend self

    # Scans through a string looking for the interoplation-opening `#{`
    # and, when it's found, yields the scanner to the calling code
    # so it can handle it properly.
    #
    # The scanner will have any backslashes immediately in front of the `#{`
    # as the second capture group (`scan[2]`),
    # and the text prior to that as the first (`scan[1]`).
    #
    # @yieldparam scan [StringScanner] The scanner scanning through the string
    # @return [String] The text remaining in the scanner after all `#{`s have been processed
    def handle_interpolation(str)
      scan = StringScanner.new(str)
      yield scan while scan.scan(/(.*?)(\\*)\#\{/)
      scan.rest
    end

    # Moves a scanner through a balanced pair of characters.
    # For example:
    #
    #     Foo (Bar (Baz bang) bop) (Bang (bop bip))
    #     ^                       ^
    #     from                    to
    #
    # @param scanner [StringScanner] The string scanner to move
    # @param start [Character] The character opening the balanced pair.
    #   A `Fixnum` in 1.8, a `String` in 1.9
    # @param finish [Character] The character closing the balanced pair.
    #   A `Fixnum` in 1.8, a `String` in 1.9
    # @param count [Fixnum] The number of opening characters matched
    #   before calling this method
    # @return [(String, String)] The string matched within the balanced pair
    #   and the rest of the string.
    #   `["Foo (Bar (Baz bang) bop)", " (Bang (bop bip))"]` in the example above.
    def balance(scanner, start, finish, count = 0)
      str = ''
      scanner = StringScanner.new(scanner) unless scanner.is_a? StringScanner
      regexp = Regexp.new("(.*?)[\\#{start.chr}\\#{finish.chr}]", Regexp::MULTILINE)
      while scanner.scan(regexp)
        str << scanner.matched
        count += 1 if scanner.matched[-1] == start
        count -= 1 if scanner.matched[-1] == finish
        return [str.strip, scanner.rest] if count == 0
      end
    end

    # Formats a string for use in error messages about indentation.
    #
    # @param indentation [String] The string used for indentation
    # @param was [Boolean] Whether or not to add `"was"` or `"were"`
    #   (depending on how many characters were in `indentation`)
    # @return [String] The name of the indentation (e.g. `"12 spaces"`, `"1 tab"`)
    def human_indentation(indentation, was = false)
      if !indentation.include?(?\t)
        noun = 'space'
      elsif !indentation.include?(?\s)
        noun = 'tab'
      else
        return indentation.inspect + (was ? ' was' : '')
      end

      singular = indentation.length == 1
      if was
        was = singular ? ' was' : ' were'
      else
        was = ''
      end

      "#{indentation.length} #{noun}#{'s' unless singular}#{was}"
    end
  end
end

# haml/precompiler.rb:
module Haml
  # Handles the internal pre-compilation from Haml into Ruby code,
  # which then runs the final creation of the HTML string.
  module Precompiler
    include Haml::Util

    # Designates an XHTML/XML element.
    # @private
    ELEMENT         = ?%

    # Designates a `<div>` element with the given class.
    # @private
    DIV_CLASS       = ?.

    # Designates a `<div>` element with the given id.
    # @private
    DIV_ID          = ?#

    # Designates an XHTML/XML comment.
    # @private
    COMMENT         = ?/

    # Designates an XHTML doctype or script that is never HTML-escaped.
    # @private
    DOCTYPE         = ?!

    # Designates script, the result of which is output.
    # @private
    SCRIPT          = ?=

    # Designates script that is always HTML-escaped.
    # @private
    SANITIZE        = ?&

    # Designates script, the result of which is flattened and output.
    # @private
    FLAT_SCRIPT     = ?~

    # Designates script which is run but not output.
    # @private
    SILENT_SCRIPT   = ?-

    # When following SILENT_SCRIPT, designates a comment that is not output.
    # @private
    SILENT_COMMENT  = ?#

    # Designates a non-parsed line.
    # @private
    ESCAPE          = ?\\

    # Designates a block of filtered text.
    # @private
    FILTER          = ?:

    # Designates a non-parsed line. Not actually a character.
    # @private
    PLAIN_TEXT      = -1

    # Keeps track of the ASCII values of the characters that begin a
    # specially-interpreted line.
    # @private
    SPECIAL_CHARACTERS   = [
      ELEMENT,
      DIV_CLASS,
      DIV_ID,
      COMMENT,
      DOCTYPE,
      SCRIPT,
      SANITIZE,
      FLAT_SCRIPT,
      SILENT_SCRIPT,
      ESCAPE,
      FILTER
    ]

    # The value of the character that designates that a line is part
    # of a multiline string.
    # @private
    MULTILINE_CHAR_VALUE = ?|

    # Regex to match keywords that appear in the middle of a Ruby block
    # with lowered indentation.
    # If a block has been started using indentation,
    # lowering the indentation with one of these won't end the block.
    # For example:
    #
    #   - if foo
    #     %p yes!
    #   - else
    #     %p no!
    #
    # The block is ended after `%p no!`, because `else`
    # is a member of this array.
    # @private
    MID_BLOCK_KEYWORD_REGEX = /^-\s*(#{%w[else elsif rescue ensure when end].join('|')})\b/

    # The Regex that matches a Doctype command.
    # @private
    DOCTYPE_REGEX = /(\d(?:\.\d)?)?[\s]*([a-z]*)/i

    # The Regex that matches a literal string or symbol value
    # @private
    LITERAL_VALUE_REGEX = /:(\w*)|(["'])((?![\\#]|\2).|\\.)*\2/

    private

    # Returns the precompiled string with the preamble and postamble
    def precompiled_with_ambles(local_names)
      preamble = <<END.gsub("\n", ";")
begin
extend Haml::Helpers
_hamlout = @haml_buffer = Haml::Buffer.new(@haml_buffer, #{options_for_buffer.inspect})
_erbout = _hamlout.buffer
__in_erb_template = true
END
      postamble = <<END.gsub("\n", ";")
#{precompiled_method_return_value}
ensure
@haml_buffer = @haml_buffer.upper
end
END
      preamble + locals_code(local_names) + precompiled + postamble
    end

    # Returns the string used as the return value of the precompiled method.
    # This method exists so it can be monkeypatched to return modified values.
    def precompiled_method_return_value
      "_erbout"
    end

    def locals_code(names)
      names = names.keys if Hash == names

      names.map do |name|
        # Can't use || because someone might explicitly pass in false with a symbol
        sym_local = "_haml_locals[#{name.to_sym.inspect}]"
        str_local = "_haml_locals[#{name.to_s.inspect}]"
        "#{name} = #{sym_local}.nil? ? #{str_local} : #{sym_local}"
      end.join(';') + ';'
    end

    # @private
    class Line < Struct.new(:text, :unstripped, :full, :index, :precompiler, :eod)
      alias_method :eod?, :eod

      def tabs
        line = self
        @tabs ||= precompiler.instance_eval do
          break 0 if line.text.empty? || !(whitespace = line.full[/^\s+/])

          if @indentation.nil?
            @indentation = whitespace

            if @indentation.include?(?\s) && @indentation.include?(?\t)
              raise SyntaxError.new("Indentation can't use both tabs and spaces.", line.index)
            end

            @flat_spaces = @indentation * @template_tabs if flat?
            break 1
          end

          tabs = whitespace.length / @indentation.length
          break tabs if whitespace == @indentation * tabs
          break @template_tabs if flat? && whitespace =~ /^#{@indentation * @template_tabs}/

          raise SyntaxError.new(<<END.strip.gsub("\n", ' '), line.index)
Inconsistent indentation: #{Haml::Shared.human_indentation whitespace, true} used for indentation,
but the rest of the document was indented using #{Haml::Shared.human_indentation @indentation}.
END
        end
      end
    end

    def precompile
      @haml_comment = @dont_indent_next_line = @dont_tab_up_next_text = false
      @indentation = nil
      @line = next_line
      resolve_newlines
      newline

      raise SyntaxError.new("Indenting at the beginning of the document is illegal.", @line.index) if @line.tabs != 0

      while next_line
        process_indent(@line) unless @line.text.empty?

        if flat?
          push_flat(@line)
          @line = @next_line
          newline
          next
        end

        process_line(@line.text, @line.index) unless @line.text.empty? || @haml_comment

        if !flat? && @next_line.tabs - @line.tabs > 1
          raise SyntaxError.new("The line was indented #{@next_line.tabs - @line.tabs} levels deeper than the previous line.", @next_line.index)
        end

        resolve_newlines unless @next_line.eod?
        @line = @next_line
        newline unless @next_line.eod?
      end

      # Close all the open tags
      close until @to_close_stack.empty?
      flush_merged_text
    end

    # Processes and deals with lowering indentation.
    def process_indent(line)
      return unless line.tabs <= @template_tabs && @template_tabs > 0

      to_close = @template_tabs - line.tabs
      to_close.times {|i| close unless to_close - 1 - i == 0 && mid_block_keyword?(line.text)}
    end

    # Processes a single line of Haml.
    #
    # This method doesn't return anything; it simply processes the line and
    # adds the appropriate code to `@precompiled`.
    def process_line(text, index)
      @index = index + 1

      case text[0]
      when DIV_CLASS; render_div(text)
      when DIV_ID
        return push_plain(text) if text[1] == ?{
        render_div(text)
      when ELEMENT; render_tag(text)
      when COMMENT; render_comment(text[1..-1].strip)
      when SANITIZE
        return push_plain(text[3..-1].strip, :escape_html => true) if text[1..2] == "=="
        return push_script(text[2..-1].strip, :escape_html => true) if text[1] == SCRIPT
        return push_flat_script(text[2..-1].strip, :escape_html => true) if text[1] == FLAT_SCRIPT
        return push_plain(text[1..-1].strip, :escape_html => true) if text[1] == ?\s
        push_plain text
      when SCRIPT
        return push_plain(text[2..-1].strip) if text[1] == SCRIPT
        push_script(text[1..-1])
      when FLAT_SCRIPT; push_flat_script(text[1..-1])
      when SILENT_SCRIPT
        return start_haml_comment if text[1] == SILENT_COMMENT

        raise SyntaxError.new(<<END.rstrip, index) if text[1..-1].strip == "end"
You don't need to use "- end" in Haml. Use indentation instead:
- if foo?
  %strong Foo!
- else
  Not foo.
END

        push_silent(text[1..-1], true)
        newline_now

        # Handle stuff like - end.join("|")
        @to_close_stack.last << false if text =~ /^-\s*end\b/ && !block_opened?

        case_stmt = text =~ /^-\s*case\b/
        keyword = mid_block_keyword?(text)
        block = block_opened? && !keyword

        # It's important to preserve tabulation modification for keywords
        # that involve choosing between posible blocks of code.
        if %w[else elsif when].include?(keyword)
          # @to_close_stack may not have a :script on top
          # when the preceding "- if" has nothing nested
          if @to_close_stack.last && @to_close_stack.last.first == :script
            @dont_indent_next_line, @dont_tab_up_next_text = @to_close_stack.last[1..2]
          else
            push_and_tabulate([:script, @dont_indent_next_line, @dont_tab_up_next_text])
          end

          # when is unusual in that either it will be indented twice,
          # or the case won't have created its own indentation
          if keyword == "when"
            push_and_tabulate([:script, @dont_indent_next_line, @dont_tab_up_next_text, false])
          end
        elsif block || case_stmt
          push_and_tabulate([:script, @dont_indent_next_line, @dont_tab_up_next_text])
        elsif block && case_stmt
          push_and_tabulate([:script, @dont_indent_next_line, @dont_tab_up_next_text])
        end
      when FILTER; start_filtered(text[1..-1].downcase)
      when DOCTYPE
        return render_doctype(text) if text[0...3] == '!!!'
        return push_plain(text[3..-1].strip, :escape_html => false) if text[1..2] == "=="
        return push_script(text[2..-1].strip, :escape_html => false) if text[1] == SCRIPT
        return push_flat_script(text[2..-1].strip, :escape_html => false) if text[1] == FLAT_SCRIPT
        return push_plain(text[1..-1].strip, :escape_html => false) if text[1] == ?\s
        push_plain text
      when ESCAPE; push_plain text[1..-1]
      else push_plain text
      end
    end

    # If the text is a silent script text with one of Ruby's mid-block keywords,
    # returns the name of that keyword.
    # Otherwise, returns nil.
    def mid_block_keyword?(text)
      text[MID_BLOCK_KEYWORD_REGEX, 1]
    end

    # Evaluates `text` in the context of the scope object, but
    # does not output the result.
    def push_silent(text, can_suppress = false)
      flush_merged_text
      return if can_suppress && options[:suppress_eval]
      @precompiled << "#{text};"
    end

    # Adds `text` to `@buffer` with appropriate tabulation
    # without parsing it.
    def push_merged_text(text, tab_change = 0, indent = true)
      text = !indent || @dont_indent_next_line || @options[:ugly] ? text : "#{'  ' * @output_tabs}#{text}"
      @to_merge << [:text, text, tab_change]
      @dont_indent_next_line = false
    end

    # Concatenate `text` to `@buffer` without tabulation.
    def concat_merged_text(text)
      @to_merge << [:text, text, 0]
    end

    def push_text(text, tab_change = 0)
      push_merged_text("#{text}\n", tab_change)
    end

    def flush_merged_text
      return if @to_merge.empty?

      str = ""
      mtabs = 0
      newlines = 0
      @to_merge.each do |type, val, tabs|
        case type
        when :text
          str << val.inspect[1...-1]
          mtabs += tabs
        when :script
          if mtabs != 0 && !@options[:ugly]
            val = "_hamlout.adjust_tabs(#{mtabs}); " + val
          end
          str << "\#{#{"\n" * newlines}#{val}}"
          mtabs = 0
          newlines = 0
        when :newlines
          newlines += val
        else
          raise SyntaxError.new("[HAML BUG] Undefined entry in Haml::Precompiler@to_merge.")
        end
      end

      @precompiled <<
        if @options[:ugly]
          "_hamlout.buffer << \"#{str}\";"
        else
          "_hamlout.push_text(\"#{str}\", #{mtabs}, #{@dont_tab_up_next_text.inspect});"
        end
      @precompiled << "\n" * newlines
      @to_merge = []
      @dont_tab_up_next_text = false
    end

    # Renders a block of text as plain text.
    # Also checks for an illegally opened block.
    def push_plain(text, options = {})
      if block_opened?
        raise SyntaxError.new("Illegal nesting: nesting within plain text is illegal.", @next_line.index)
      end

      if contains_interpolation?(text)
        options[:escape_html] = self.options[:escape_html] if options[:escape_html].nil?
        push_script(
          unescape_interpolation(text, :escape_html => options[:escape_html]),
          :escape_html => false)
      else
        push_text text
      end
    end

    # Adds +text+ to `@buffer` while flattening text.
    def push_flat(line)
      text = line.full.dup
      text = "" unless text.gsub!(/^#{@flat_spaces}/, '')
      @filter_buffer << "#{text}\n"
    end

    # Causes `text` to be evaluated in the context of
    # the scope object and the result to be added to `@buffer`.
    #
    # If `opts[:preserve_script]` is true, Haml::Helpers#find_and_flatten is run on
    # the result before it is added to `@buffer`
    def push_script(text, opts = {})
      raise SyntaxError.new("There's no Ruby code for = to evaluate.") if text.empty?
      return if options[:suppress_eval]
      opts[:escape_html] = options[:escape_html] if opts[:escape_html].nil?

      args = %w[preserve_script in_tag preserve_tag escape_html nuke_inner_whitespace]
      args.map! {|name| opts[name.to_sym]}
      args << !block_opened? << @options[:ugly]

      no_format = @options[:ugly] &&
        !(opts[:preserve_script] || opts[:preserve_tag] || opts[:escape_html])
      output_expr = "(#{text}\n)"
      static_method = "_hamlout.#{static_method_name(:format_script, *args)}"

      # Prerender tabulation unless we're in a tag
      push_merged_text '' unless opts[:in_tag]

      unless block_opened?
        @to_merge << [:script, no_format ? "#{text}\n" : "#{static_method}(#{output_expr});"]
        concat_merged_text("\n") unless opts[:in_tag] || opts[:nuke_inner_whitespace]
        @newlines -= 1
        return
      end

      flush_merged_text

      push_silent "haml_temp = #{text}"
      newline_now
      push_and_tabulate([:loud, "_hamlout.buffer << #{no_format ? "haml_temp.to_s;" : "#{static_method}(haml_temp);"}",
        !(opts[:in_tag] || opts[:nuke_inner_whitespace] || @options[:ugly])])
    end

    # Causes `text` to be evaluated, and Haml::Helpers#find_and_flatten
    # to be run on it afterwards.
    def push_flat_script(text, options = {})
      flush_merged_text

      raise SyntaxError.new("There's no Ruby code for ~ to evaluate.") if text.empty?
      push_script(text, options.merge(:preserve_script => true))
    end

    def start_haml_comment
      return unless block_opened?

      @haml_comment = true
      push_and_tabulate([:haml_comment])
    end

    # Closes the most recent item in `@to_close_stack`.
    def close
      tag, *rest = @to_close_stack.pop
      send("close_#{tag}", *rest)
    end

    # Puts a line in `@precompiled` that will add the closing tag of
    # the most recently opened tag.
    def close_element(value)
      tag, nuke_outer_whitespace, nuke_inner_whitespace = value
      @output_tabs -= 1 unless nuke_inner_whitespace
      @template_tabs -= 1
      rstrip_buffer! if nuke_inner_whitespace
      push_merged_text("</#{tag}>" + (nuke_outer_whitespace ? "" : "\n"),
                       nuke_inner_whitespace ? 0 : -1, !nuke_inner_whitespace)
      @dont_indent_next_line = nuke_outer_whitespace
    end

    # Closes a Ruby block.
    def close_script(_1, _2, push_end = true)
      push_silent("end", true) if push_end
      @template_tabs -= 1
    end

    # Closes a comment.
    def close_comment(has_conditional)
      @output_tabs -= 1
      @template_tabs -= 1
      close_tag = has_conditional ? "<![endif]-->" : "-->"
      push_text(close_tag, -1)
    end

    # Closes a loud Ruby block.
    def close_loud(command, add_newline, push_end = true)
      push_silent('end', true) if push_end
      @precompiled << command
      @template_tabs -= 1
      concat_merged_text("\n") if add_newline
    end

    # Closes a filtered block.
    def close_filtered(filter)
      filter.internal_compile(self, @filter_buffer)
      @flat = false
      @flat_spaces = nil
      @filter_buffer = nil
      @template_tabs -= 1
    end

    def close_haml_comment
      @haml_comment = false
      @template_tabs -= 1
    end

    def close_nil(*args)
      @template_tabs -= 1
    end

    # This is a class method so it can be accessed from {Haml::Helpers}.
    #
    # Iterates through the classes and ids supplied through `.`
    # and `#` syntax, and returns a hash with them as attributes,
    # that can then be merged with another attributes hash.
    def self.parse_class_and_id(list)
      attributes = {}
      list.scan(/([#.])([-_a-zA-Z0-9]+)/) do |type, property|
        case type
        when '.'
          if attributes['class']
            attributes['class'] += " "
          else
            attributes['class'] = ""
          end
          attributes['class'] += property
        when '#'; attributes['id'] = property
        end
      end
      attributes
    end

    def parse_static_hash(text)
      attributes = {}
      scanner = StringScanner.new(text)
      scanner.scan(/\s+/)
      until scanner.eos?
        return unless key = scanner.scan(LITERAL_VALUE_REGEX)
        return unless scanner.scan(/\s*=>\s*/)
        return unless value = scanner.scan(LITERAL_VALUE_REGEX)
        return unless scanner.scan(/\s*(?:,|$)\s*/)
        attributes[eval(key).to_s] = eval(value).to_s
      end
      text.count("\n").times { newline }
      attributes
    end

    # This is a class method so it can be accessed from Buffer.
    def self.build_attributes(is_html, attr_wrapper, attributes = {})
      quote_escape = attr_wrapper == '"' ? "&quot;" : "&apos;"
      other_quote_char = attr_wrapper == '"' ? "'" : '"'

      result = attributes.collect do |attr, value|
        next if value.nil?

        if value == true
          next " #{attr}" if is_html
          next " #{attr}=#{attr_wrapper}#{attr}#{attr_wrapper}"
        elsif value == false
          next
        end

        value = Haml::Helpers.preserve(Haml::Helpers.escape_once(value.to_s))
        # We want to decide whether or not to escape quotes
        value.gsub!('&quot;', '"')
        this_attr_wrapper = attr_wrapper
        if value.include? attr_wrapper
          if value.include? other_quote_char
            value = value.gsub(attr_wrapper, quote_escape)
          else
            this_attr_wrapper = other_quote_char
          end
        end
        " #{attr}=#{this_attr_wrapper}#{value}#{this_attr_wrapper}"
      end
      result.compact.sort.join
    end

    def prerender_tag(name, self_close, attributes)
      attributes_string = Precompiler.build_attributes(html?, @options[:attr_wrapper], attributes)
      "<#{name}#{attributes_string}#{self_close && xhtml? ? ' /' : ''}>"
    end

    # Parses a line into tag_name, attributes, attributes_hash, object_ref, action, value
    def parse_tag(line)
      raise SyntaxError.new("Invalid tag: \"#{line}\".") unless match = line.scan(/%([-:\w]+)([-\w\.\#]*)(.*)/)[0]
      tag_name, attributes, rest = match
      new_attributes_hash = old_attributes_hash = last_line = object_ref = nil
      attributes_hashes = []
      while rest
        case rest[0]
        when ?{
          break if old_attributes_hash
          old_attributes_hash, rest, last_line = parse_old_attributes(rest)
          attributes_hashes << [:old, old_attributes_hash]
        when ?(
          break if new_attributes_hash
          new_attributes_hash, rest, last_line = parse_new_attributes(rest)
          attributes_hashes << [:new, new_attributes_hash]
        when ?[
          break if object_ref
          object_ref, rest = balance(rest, ?[, ?])
        else; break
        end
      end

      if rest
        nuke_whitespace, action, value = rest.scan(/(<>|><|[><])?([=\/\~&!])?(.*)?/)[0]
        nuke_whitespace ||= ''
        nuke_outer_whitespace = nuke_whitespace.include? '>'
        nuke_inner_whitespace = nuke_whitespace.include? '<'
      end

      value = value.to_s.strip
      [tag_name, attributes, attributes_hashes, object_ref, nuke_outer_whitespace,
       nuke_inner_whitespace, action, value, last_line || @index]
    end

    def parse_old_attributes(line)
      line = line.dup
      last_line = @index

      begin
        attributes_hash, rest = balance(line, ?{, ?})
      rescue SyntaxError => e
        if line.strip[-1] == ?, && e.message == "Unbalanced brackets."
          line << "\n" << @next_line.text
          last_line += 1
          next_line
          retry
        end

        raise e
      end

      attributes_hash = attributes_hash[1...-1] if attributes_hash
      return attributes_hash, rest, last_line
    end

    def parse_new_attributes(line)
      line = line.dup
      scanner = StringScanner.new(line)
      last_line = @index
      attributes = {}

      scanner.scan(/\(\s*/)
      loop do
        name, value = parse_new_attribute(scanner)
        break if name.nil?

        if name == false
          text = (Haml::Shared.balance(line, ?(, ?)) || [line]).first
          raise Haml::SyntaxError.new("Invalid attribute list: #{text.inspect}.", last_line - 1)
        end
        attributes[name] = value
        scanner.scan(/\s*/)

        if scanner.eos?
          line << " " << @next_line.text
          last_line += 1
          next_line
          scanner.scan(/\s*/)
        end
      end

      static_attributes = {}
      dynamic_attributes = "{"
      attributes.each do |name, (type, val)|
        if type == :static
          static_attributes[name] = val
        else
          dynamic_attributes << name.inspect << " => " << val << ","
        end
      end
      dynamic_attributes << "}"
      dynamic_attributes = nil if dynamic_attributes == "{}"

      return [static_attributes, dynamic_attributes], scanner.rest, last_line
    end

    def parse_new_attribute(scanner)
      unless name = scanner.scan(/[-:\w]+/)
        return if scanner.scan(/\)/)
        return false
      end

      scanner.scan(/\s*/)
      return name, [:static, true] unless scanner.scan(/=/) #/end

      scanner.scan(/\s*/)
      unless quote = scanner.scan(/["']/)
        return false unless var = scanner.scan(/(@@?|\$)?\w+/)
        return name, [:dynamic, var]
      end

      re = /((?:\\.|\#(?!\{)|[^#{quote}\\#])*)(#{quote}|#\{)/
      content = []
      loop do
        return false unless scanner.scan(re)
        content << [:str, scanner[1].gsub(/\\(.)/, '\1')]
        break if scanner[2] == quote
        content << [:ruby, balance(scanner, ?{, ?}, 1).first[0...-1]]
      end

      return name, [:static, content.first[1]] if content.size == 1
      return name, [:dynamic,
        '"' + content.map {|(t, v)| t == :str ? v.inspect[1...-1] : "\#{#{v}}"}.join + '"']
    end

    # Parses a line that will render as an XHTML tag, and adds the code that will
    # render that tag to `@precompiled`.
    def render_tag(line)
      tag_name, attributes, attributes_hashes, object_ref, nuke_outer_whitespace,
        nuke_inner_whitespace, action, value, last_line = parse_tag(line)

      raise SyntaxError.new("Illegal element: classes and ids must have values.") if attributes =~ /[\.#](\.|#|\z)/

      # Get rid of whitespace outside of the tag if we need to
      rstrip_buffer! if nuke_outer_whitespace

      preserve_tag = options[:preserve].include?(tag_name)
      nuke_inner_whitespace ||= preserve_tag
      preserve_tag &&= !options[:ugly]

      escape_html = (action == '&' || (action != '!' && @options[:escape_html]))

      case action
      when '/'; self_closing = true
      when '~'; parse = preserve_script = true
      when '='
        parse = true
        if value[0] == ?=
          value = unescape_interpolation(value[1..-1].strip, :escape_html => escape_html)
          escape_html = false
        end
      when '&', '!'
        if value[0] == ?= || value[0] == ?~
          parse = true
          preserve_script = (value[0] == ?~)
          if value[1] == ?=
            value = unescape_interpolation(value[2..-1].strip, :escape_html => escape_html)
            escape_html = false
          else
            value = value[1..-1].strip
          end
        elsif contains_interpolation?(value)
          value = unescape_interpolation(value, :escape_html => escape_html)
          parse = true
          escape_html = false
        end
      else
        if contains_interpolation?(value)
          value = unescape_interpolation(value, :escape_html => escape_html)
          parse = true
          escape_html = false
        end
      end

      if parse && @options[:suppress_eval]
        parse = false
        value = ''
      end

      object_ref = "nil" if object_ref.nil? || @options[:suppress_eval]

      attributes = Precompiler.parse_class_and_id(attributes)
      attributes_hashes.map! do |syntax, attributes_hash|
        if syntax == :old
          static_attributes = parse_static_hash(attributes_hash)
          attributes_hash = nil if static_attributes || @options[:suppress_eval]
        else
          static_attributes, attributes_hash = attributes_hash
        end
        Buffer.merge_attrs(attributes, static_attributes) if static_attributes
        attributes_hash
      end.compact!

      raise SyntaxError.new("Illegal nesting: nesting within a self-closing tag is illegal.", @next_line.index) if block_opened? && self_closing
      raise SyntaxError.new("Illegal nesting: content can't be both given on the same line as %#{tag_name} and nested within it.", @next_line.index) if block_opened? && !value.empty?
      raise SyntaxError.new("There's no Ruby code for #{action} to evaluate.", last_line - 1) if parse && value.empty?
      raise SyntaxError.new("Self-closing tags can't have content.", last_line - 1) if self_closing && !value.empty?

      self_closing ||= !!(!block_opened? && value.empty? && @options[:autoclose].any? {|t| t === tag_name})
      value = nil if value.empty? && (block_opened? || self_closing)

      dont_indent_next_line =
        (nuke_outer_whitespace && !block_opened?) ||
        (nuke_inner_whitespace && block_opened?)

      # Check if we can render the tag directly to text and not process it in the buffer
      if object_ref == "nil" && attributes_hashes.empty? && !preserve_script
        tag_closed = !block_opened? && !self_closing && !parse

        open_tag  = prerender_tag(tag_name, self_closing, attributes)
        if tag_closed
          open_tag << "#{value}</#{tag_name}>"
          open_tag << "\n" unless nuke_outer_whitespace
        else
          open_tag << "\n" unless parse || nuke_inner_whitespace || (self_closing && nuke_outer_whitespace)
        end

        push_merged_text(open_tag, tag_closed || self_closing || nuke_inner_whitespace ? 0 : 1,
                         !nuke_outer_whitespace)

        @dont_indent_next_line = dont_indent_next_line
        return if tag_closed
      else
        flush_merged_text
        content = parse ? 'nil' : value.inspect
        if attributes_hashes.empty?
          attributes_hashes = ''
        elsif attributes_hashes.size == 1
          attributes_hashes = ", #{attributes_hashes.first}"
        else
          attributes_hashes = ", (#{attributes_hashes.join(").merge(")})"
        end

        args = [tag_name, self_closing, !block_opened?, preserve_tag, escape_html,
                attributes, nuke_outer_whitespace, nuke_inner_whitespace
               ].map { |v| v.inspect }.join(', ')
        push_silent "_hamlout.open_tag(#{args}, #{object_ref}, #{content}#{attributes_hashes})"
        @dont_tab_up_next_text = @dont_indent_next_line = dont_indent_next_line
      end

      return if self_closing

      if value.nil?
        push_and_tabulate([:element, [tag_name, nuke_outer_whitespace, nuke_inner_whitespace]])
        @output_tabs += 1 unless nuke_inner_whitespace
        return
      end

      if parse
        push_script(value, :preserve_script => preserve_script, :in_tag => true,
          :preserve_tag => preserve_tag, :escape_html => escape_html,
          :nuke_inner_whitespace => nuke_inner_whitespace)
        concat_merged_text("</#{tag_name}>" + (nuke_outer_whitespace ? "" : "\n"))
      end
    end

    # Renders a line that creates an XHTML tag and has an implicit div because of
    # `.` or `#`.
    def render_div(line)
      render_tag('%div' + line)
    end

    # Renders an XHTML comment.
    def render_comment(line)
      conditional, line = balance(line, ?[, ?]) if line[0] == ?[
      line.strip!
      conditional << ">" if conditional

      if block_opened? && !line.empty?
        raise SyntaxError.new('Illegal nesting: nesting within a tag that already has content is illegal.', @next_line.index)
      end

      open = "<!--#{conditional}"

      # Render it statically if possible
      unless line.empty?
        return push_text("#{open} #{line} #{conditional ? "<![endif]-->" : "-->"}")
      end

      push_text(open, 1)
      @output_tabs += 1
      push_and_tabulate([:comment, !conditional.nil?])
      unless line.empty?
        push_text(line)
        close
      end
    end

    # Renders an XHTML doctype or XML shebang.
    def render_doctype(line)
      raise SyntaxError.new("Illegal nesting: nesting within a header command is illegal.", @next_line.index) if block_opened?
      doctype = text_for_doctype(line)
      push_text doctype if doctype
    end

    def text_for_doctype(text)
      text = text[3..-1].lstrip.downcase
      if text.index("xml") == 0
        return nil if html?
        wrapper = @options[:attr_wrapper]
        return "<?xml version=#{wrapper}1.0#{wrapper} encoding=#{wrapper}#{text.split(' ')[1] || "utf-8"}#{wrapper} ?>"
      end

      if html5?
        '<!DOCTYPE html>'
      else
        version, type = text.scan(DOCTYPE_REGEX)[0]

        if xhtml?
          if version == "1.1"
            '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">'
          elsif version == "5"
            '<!DOCTYPE html>'
          else
            case type
            when "strict";   '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">'
            when "frameset"; '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Frameset//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd">'
            when "mobile";   '<!DOCTYPE html PUBLIC "-//WAPFORUM//DTD XHTML Mobile 1.2//EN" "http://www.openmobilealliance.org/tech/DTD/xhtml-mobile12.dtd">'
            when "basic";    '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML Basic 1.1//EN" "http://www.w3.org/TR/xhtml-basic/xhtml-basic11.dtd">'
            else             '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">'
            end
          end

        elsif html4?
          case type
          when "strict";   '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">'
          when "frameset"; '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Frameset//EN" "http://www.w3.org/TR/html4/frameset.dtd">'
          else             '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">'
          end
        end
      end
    end

    # Starts a filtered block.
    def start_filtered(name)
      raise Error.new("Invalid filter name \":#{name}\".") unless name =~ /^\w+$/
      raise Error.new("Filter \"#{name}\" is not defined.") unless filter = Filters.defined[name]

      push_and_tabulate([:filtered, filter])
      @flat = true
      @filter_buffer = String.new

      # If we don't know the indentation by now, it'll be set in Line#tabs
      @flat_spaces = @indentation * @template_tabs if @indentation
    end

    def raw_next_line
      text = @template.shift
      return unless text

      index = @template_index
      @template_index += 1

      return text, index
    end

    def next_line
      text, index = raw_next_line
      return unless text

      # :eod is a special end-of-document marker
      line =
        if text == :eod
          Line.new '-#', '-#', '-#', index, self, true
        else
          Line.new text.strip, text.lstrip.chomp, text, index, self, false
        end

      # `flat?' here is a little outdated,
      # so we have to manually check if either the previous or current line
      # closes the flat block,
      # as well as whether a new block is opened
      @line.tabs if @line
      unless (flat? && !closes_flat?(line) && !closes_flat?(@line)) ||
          (@line && @line.text[0] == ?: && line.full =~ %r[^#{@line.full[/^\s+/]}\s])
        if line.text.empty?
          newline
          return next_line
        end

        handle_multiline(line)
      end

      @next_line = line
    end

    def closes_flat?(line)
      line && !line.text.empty? && line.full !~ /^#{@flat_spaces}/
    end

    def un_next_line(line)
      @template.unshift line
      @template_index -= 1
    end

    def handle_multiline(line)
      if is_multiline?(line.text)
        line.text.slice!(-1)
        while new_line = raw_next_line.first
          break if new_line == :eod
          newline and next if new_line.strip.empty?
          break unless is_multiline?(new_line.strip)
          line.text << new_line.strip[0...-1]
          newline
        end
        un_next_line new_line
        resolve_newlines
      end
    end

    # Checks whether or not +line+ is in a multiline sequence.
    def is_multiline?(text)
      text && text.length > 1 && text[-1] == MULTILINE_CHAR_VALUE && text[-2] == ?\s
    end

    def contains_interpolation?(str)
      str.include?('#{')
    end

    def unescape_interpolation(str, opts = {})
      res = ''
      rest = Haml::Shared.handle_interpolation str.dump do |scan|
        escapes = (scan[2].size - 1) / 2
        res << scan.matched[0...-3 - escapes]
        if escapes % 2 == 1
          res << '#{'
        else
          content = eval('"' + balance(scan, ?{, ?}, 1)[0][0...-1] + '"')
          content = "Haml::Helpers.html_escape(#{content})" if opts[:escape_html]
          res << '#{' + content + "}"# Use eval to get rid of string escapes
        end
      end
      res + rest
    end

    def balance(*args)
      res = Haml::Shared.balance(*args)
      return res if res
      raise SyntaxError.new("Unbalanced brackets.")
    end

    def block_opened?
      !flat? && @next_line.tabs > @line.tabs
    end

    # Pushes value onto `@to_close_stack` and increases
    # `@template_tabs`.
    def push_and_tabulate(value)
      @to_close_stack.push(value)
      @template_tabs += 1
    end

    def flat?
      @flat
    end

    def newline
      @newlines += 1
    end

    def newline_now
      @precompiled << "\n"
      @newlines -= 1
    end

    def resolve_newlines
      return unless @newlines > 0
      @to_merge << [:newlines, @newlines]
      @newlines = 0
    end

    # Get rid of and whitespace at the end of the buffer
    # or the merged text
    def rstrip_buffer!(index = -1)
      last = @to_merge[index]
      if last.nil?
        push_silent("_hamlout.rstrip!", false)
        @dont_tab_up_next_text = true
        return
      end

      case last.first
      when :text
        last[1].rstrip!
        if last[1].empty?
          @to_merge.slice! index
          rstrip_buffer! index
        end
      when :script
        last[1].gsub!(/\(haml_temp, (.*?)\);$/, '(haml_temp.rstrip, \1);')
        rstrip_buffer! index - 1
      when :newlines
        rstrip_buffer! index - 1
      else
        raise SyntaxError.new("[HAML BUG] Undefined entry in Haml::Precompiler@to_merge.")
      end
    end
  end
end

# haml/filters.rb:
module Haml
  # The module containing the default Haml filters,
  # as well as the base module, {Haml::Filters::Base}.
  #
  # @see Haml::Filters::Base
  module Filters
    # @return [{String => Haml::Filters::Base}] a hash of filter names to classes
    def self.defined
      @defined ||= {}
    end

    # The base module for Haml filters.
    # User-defined filters should be modules including this module.
    # The name of the filter is taken by downcasing the module name.
    # For instance, if the module is named `FooBar`, the filter will be `:foobar`.
    #
    # A user-defined filter should override either \{#render} or {\#compile}.
    # \{#render} is the most common.
    # It takes a string, the filter source,
    # and returns another string, the result of the filter.
    # For example, the following will define a filter named `:sass`:
    #
    #     module Haml::Filters::Sass
    #       include Haml::Filters::Base
    #
    #       def render(text)
    #         ::Sass::Engine.new(text).render
    #       end
    #     end
    #
    # For details on overriding \{#compile}, see its documentation.
    #
    # Note that filters overriding \{#render} automatically support `#{}`
    # for interpolating Ruby code.
    # Those overriding \{#compile} will need to add such support manually
    # if it's desired.
    module Base
      # This method is automatically called when {Base} is included in a module.
      # It automatically defines a filter
      # with the downcased name of that module.
      # For example, if the module is named `FooBar`, the filter will be `:foobar`.
      #
      # @param base [Module, Class] The module that this is included in
      def self.included(base)
        Filters.defined[base.name.split("::").last.downcase] = base
        base.extend(base)
      end

      # Takes the source text that should be passed to the filter
      # and returns the result of running the filter on that string.
      #
      # This should be overridden in most individual filter modules
      # to render text with the given filter.
      # If \{#compile} is overridden, however, \{#render} doesn't need to be.
      #
      # @param text [String] The source text for the filter to process
      # @return [String] The filtered result
      # @raise [Haml::Error] if it's not overridden
      def render(text)
        raise Error.new("#{self.inspect}#render not defined!")
      end

      # Same as \{#render}, but takes a {Haml::Engine} options hash as well.
      # It's only safe to rely on options made available in {Haml::Engine#options\_for\_buffer}.
      #
      # @see #render
      # @param text [String] The source text for the filter to process
      # @return [String] The filtered result
      # @raise [Haml::Error] if it or \{#render} isn't overridden
      def render_with_options(text, options)
        render(text)
      end

      # Same as \{#compile}, but requires the necessary files first.
      # *This is used by {Haml::Engine} and is not intended to be overridden or used elsewhere.*
      #
      # @see #compile
      def internal_compile(*args)
        resolve_lazy_requires
        compile(*args)
      end

      # This should be overridden when a filter needs to have access to the Haml evaluation context.
      # Rather than applying a filter to a string at compile-time,
      # \{#compile} uses the {Haml::Precompiler} instance to compile the string to Ruby code
      # that will be executed in the context of the active Haml template.
      #
      # Warning: the {Haml::Precompiler} interface is neither well-documented
      # nor guaranteed to be stable.
      # If you want to make use of it, you'll probably need to look at the source code
      # and should test your filter when upgrading to new Haml versions.
      #
      # @param precompiler [Haml::Precompiler] The precompiler instance
      # @param text [String] The text of the filter
      # @raise [Haml::Error] if none of \{#compile}, \{#render}, and \{#render_with_options} are overridden
      def compile(precompiler, text)
        resolve_lazy_requires
        filter = self
        precompiler.instance_eval do
          if contains_interpolation?(text)
            return if options[:suppress_eval]

            push_script <<RUBY, :escape_html => false
find_and_preserve(#{filter.inspect}.render_with_options(#{unescape_interpolation(text)}, _hamlout.options))
RUBY
            return
          end

          rendered = Haml::Helpers::find_and_preserve(filter.render_with_options(text, precompiler.options), precompiler.options[:preserve])

          if !options[:ugly]
            push_text(rendered.rstrip.gsub("\n", "\n#{'  ' * @output_tabs}"))
          else
            push_text(rendered.rstrip)
          end
        end
      end

      # This becomes a class method of modules that include {Base}.
      # It allows the module to specify one or more Ruby files
      # that Haml should try to require when compiling the filter.
      #
      # The first file specified is tried first, then the second, etc.
      # If none are found, the compilation throws an exception.
      #
      # For example:
      #
      #     module Haml::Filters::Markdown
      #       lazy_require 'rdiscount', 'peg_markdown', 'maruku', 'bluecloth'
      #
      #       ...
      #     end
      #
      # @param reqs [Array<String>] The requires to run
      def lazy_require(*reqs)
        @lazy_requires = reqs
      end

      private

      def resolve_lazy_requires
        return unless @lazy_requires

        @lazy_requires[0...-1].each do |req|
          begin
            @required = req
            require @required
            return
          rescue LoadError; end # RCov doesn't see this, but it is run
        end

        begin
          @required = @lazy_requires[-1]
          require @required
        rescue LoadError => e
          classname = self.name.match(/\w+$/)[0]

          if @lazy_requires.size == 1
            raise Error.new("Can't run #{classname} filter; required file '#{@lazy_requires.first}' not found")
          else
            raise Error.new("Can't run #{classname} filter; required #{@lazy_requires.map { |r| "'#{r}'" }.join(' or ')}, but none were found")
          end
        end
      end
    end
  end
end

begin
  require 'rubygems'
rescue LoadError; end

module Haml
  module Filters
    # Does not parse the filtered text.
    # This is useful for large blocks of text without HTML tags,
    # when you don't want lines starting with `.` or `-`
    # to be parsed.
    module Plain
      include Base

      # @see Base#render
      def render(text); text; end
    end

    # Surrounds the filtered text with `<script>` and CDATA tags.
    # Useful for including inline Javascript.
    module Javascript
      include Base

      # @see Base#render_with_options
      def render_with_options(text, options)
        <<END
<script type=#{options[:attr_wrapper]}text/javascript#{options[:attr_wrapper]}>
  //<![CDATA[
    #{text.rstrip.gsub("\n", "\n    ")}
  //]]>
</script>
END
      end
    end

    # Surrounds the filtered text with `<style>` and CDATA tags.
    # Useful for including inline CSS.
    module Css
      include Base

      # @see Base#render_with_options
      def render_with_options(text, options)
        <<END
<style type=#{options[:attr_wrapper]}text/css#{options[:attr_wrapper]}>
  /*<![CDATA[*/
    #{text.rstrip.gsub("\n", "\n    ")}
  /*]]>*/
</style>
END
      end
    end

    # Surrounds the filtered text with CDATA tags.
    module Cdata
      include Base

      # @see Base#render
      def render(text)
        "<![CDATA[#{("\n" + text).rstrip.gsub("\n", "\n    ")}\n]]>"
      end
    end

    # Works the same as {Plain}, but HTML-escapes the text
    # before placing it in the document.
    module Escaped
      include Base

      # @see Base#render
      def render(text)
        Haml::Helpers.html_escape text
      end
    end

    # Parses the filtered text with the normal Ruby interpreter.
    # All output sent to `$stdout`, such as with `puts`,
    # is output into the Haml document.
    # Not available if the {file:HAML_REFERENCE.md#suppress_eval-option `:suppress_eval`} option is set to true.
    # The Ruby code is evaluated in the same context as the Haml template.
    module Ruby
      include Base
      lazy_require 'stringio'

      # @see Base#compile
      def compile(precompiler, text)
        return if precompiler.options[:suppress_eval]
        precompiler.instance_eval do
          push_silent <<-FIRST.gsub("\n", ';') + text + <<-LAST.gsub("\n", ';')
            _haml_old_stdout = $stdout
            $stdout = StringIO.new(_hamlout.buffer, 'a')
          FIRST
            _haml_old_stdout, $stdout = $stdout, _haml_old_stdout
            _haml_old_stdout.close
          LAST
        end
      end
    end

    # Inserts the filtered text into the template with whitespace preserved.
    # `preserve`d blocks of text aren't indented,
    # and newlines are replaced with the HTML escape code for newlines,
    # to preserve nice-looking output.
    #
    # @see Haml::Helpers#preserve
    module Preserve
      include Base

      # @see Base#render
      def render(text)
        Haml::Helpers.preserve text
      end
    end

    # Parses the filtered text with {Sass} to produce CSS output.
    module Sass
      include Base
      lazy_require 'sass/plugin'

      # @see Base#render
      def render(text)
        ::Sass::Engine.new(text, ::Sass::Plugin.engine_options).render
      end
    end

    # Parses the filtered text with ERB.
    # Not available if the {file:HAML_REFERENCE.md#suppress_eval-option `:suppress_eval`} option is set to true.
    # Embedded Ruby code is evaluated in the same context as the Haml template.
    module ERB
      include Base
      lazy_require 'erb'

      # @see Base#compile
      def compile(precompiler, text)
        return if precompiler.options[:suppress_eval]
        src = ::ERB.new(text).src.sub(/^#coding:.*?\n/, '').
          sub(/^_erbout = '';/, "")
        precompiler.send(:push_silent, src)
      end
    end

    # Parses the filtered text with [Textile](http://www.textism.com/tools/textile).
    # Only works if [RedCloth](http://redcloth.org) is installed.
    module Textile
      include Base
      lazy_require 'redcloth'

      # @see Base#render
      def render(text)
        ::RedCloth.new(text).to_html(:textile)
      end
    end
    RedCloth = Textile
    Filters.defined['redcloth'] = RedCloth

    # Parses the filtered text with [Markdown](http://daringfireball.net/projects/markdown).
    # Only works if [RDiscount](http://github.com/rtomayko/rdiscount),
    # [RPeg-Markdown](http://github.com/rtomayko/rpeg-markdown),
    # [Maruku](http://maruku.rubyforge.org),
    # or [BlueCloth](www.deveiate.org/projects/BlueCloth) are installed.
    module Markdown
      include Base
      lazy_require 'rdiscount', 'peg_markdown', 'maruku', 'bluecloth'

      # @see Base#render
      def render(text)
        engine = case @required
                 when 'rdiscount'
                   ::RDiscount
                 when 'peg_markdown'
                   ::PEGMarkdown
                 when 'maruku'
                   ::Maruku
                 when 'bluecloth'
                   ::BlueCloth
                 end
        engine.new(text).to_html
      end
    end

    # Parses the filtered text with [Maruku](http://maruku.rubyforge.org),
    # which has some non-standard extensions to Markdown.
    module Maruku
      include Base
      lazy_require 'maruku'

      # @see Base#render
      def render(text)
        ::Maruku.new(text).to_html
      end
    end
  end
end

# haml/error.rb:
module Haml
  # An exception raised by Haml code.
  class Error < StandardError
    # The line of the template on which the error occurred.
    #
    # @return [Fixnum]
    attr_reader :line

    # @param message [String] The error message
    # @param line [Fixnum] See \{#line}
    def initialize(message = nil, line = nil)
      super(message)
      @line = line
    end
  end

  # SyntaxError is the type of exception raised when Haml encounters an
  # ill-formatted document.
  # It's not particularly interesting,
  # except in that it's a subclass of {Haml::Error}.
  class SyntaxError < Haml::Error; end
end

# haml/engine.rb:
module Haml
  # This is the frontend for using Haml programmatically.
  # It can be directly used by the user by creating a
  # new instance and calling \{#render} to render the template.
  # For example:
  #
  #     template = File.read('templates/really_cool_template.haml')
  #     haml_engine = Haml::Engine.new(template)
  #     output = haml_engine.render
  #     puts output
  class Engine
    include Precompiler

    # The options hash.
    # See {file:HAML_REFERENCE.md#haml_options the Haml options documentation}.
    #
    # @return [{Symbol => Object}]
    attr_accessor :options

    # The indentation used in the Haml document,
    # or `nil` if the indentation is ambiguous
    # (for example, for a single-level document).
    #
    # @return [String]
    attr_accessor :indentation

    # @return [Boolean] Whether or not the format is XHTML.
    def xhtml?
      not html?
    end

    # @return [Boolean] Whether or not the format is any flavor of HTML.
    def html?
      html4? or html5?
    end

    # @return [Boolean] Whether or not the format is HTML4.
    def html4?
      @options[:format] == :html4
    end

    # @return [Boolean] Whether or not the format is HTML5.
    def html5?
      @options[:format] == :html5
    end

    # The source code that is evaluated to produce the Haml document.
    #
    # In Ruby 1.9, this is automatically converted to the correct encoding
    # (see {file:HAML_REFERENCE.md#encoding-option the `:encoding` option}).
    #
    # @return [String]
    def precompiled
      return @precompiled if ruby1_8?
      encoding = Encoding.find(@options[:encoding])
      return @precompiled.force_encoding(encoding) if encoding == Encoding::BINARY
      return @precompiled.encode(encoding)
    end

    # Precompiles the Haml template.
    #
    # @param template [String] The Haml template
    # @param options [{Symbol => Object}] An options hash;
    #   see {file:HAML_REFERENCE.md#haml_options the Haml options documentation}
    # @raise [Haml::Error] if there's a Haml syntax error in the template
    def initialize(template, options = {})
      @options = {
        :suppress_eval => false,
        :attr_wrapper => "'",

        # Don't forget to update the docs in doc-src/HAML_REFERENCE.md
        # if you update these
        :autoclose => %w[meta img link br hr input area param col base],
        :preserve => %w[textarea pre code],

        :filename => '(haml)',
        :line => 1,
        :ugly => false,
        :format => :xhtml,
        :escape_html => false,
      }
      unless ruby1_8?
        @options[:encoding] = Encoding.default_internal || "utf-8"
      end
      @options.merge! options.reject {|k, v| v.nil?}
      @index = 0

      unless [:xhtml, :html4, :html5].include?(@options[:format])
        raise Haml::Error, "Invalid format #{@options[:format].inspect}"
      end

      if @options[:encoding] && @options[:encoding].is_a?(Encoding)
        @options[:encoding] = @options[:encoding].name
      end

      template = check_encoding(template) {|msg, line| raise Haml::Error.new(msg, line)}

      # :eod is a special end-of-document marker
      @template = (template.rstrip).split(/\r\n|\r|\n/) + [:eod, :eod]
      @template_index = 0
      @to_close_stack = []
      @output_tabs = 0
      @template_tabs = 0
      @flat = false
      @newlines = 0
      @precompiled = ''
      @to_merge = []
      @tab_change  = 0

      precompile
    rescue Haml::Error => e
      if @index || e.line
        e.backtrace.unshift "#{@options[:filename]}:#{(e.line ? e.line + 1 : @index) + @options[:line] - 1}"
      end
      raise
    end

    # Processes the template and returns the result as a string.
    #
    # `scope` is the context in which the template is evaluated.
    # If it's a `Binding` or `Proc` object,
    # Haml uses it as the second argument to `Kernel#eval`;
    # otherwise, Haml just uses its `#instance_eval` context.
    #
    # Note that Haml modifies the evaluation context
    # (either the scope object or the `self` object of the scope binding).
    # It extends {Haml::Helpers}, and various instance variables are set
    # (all prefixed with `haml_`).
    # For example:
    #
    #     s = "foobar"
    #     Haml::Engine.new("%p= upcase").render(s) #=> "<p>FOOBAR</p>"
    #
    #     # s now extends Haml::Helpers
    #     s.respond_to?(:html_attrs) #=> true
    #
    # `locals` is a hash of local variables to make available to the template.
    # For example:
    #
    #     Haml::Engine.new("%p= foo").render(Object.new, :foo => "Hello, world!") #=> "<p>Hello, world!</p>"
    #
    # If a block is passed to render,
    # that block is run when `yield` is called
    # within the template.
    #
    # Due to some Ruby quirks,
    # if `scope` is a `Binding` or `Proc` object and a block is given,
    # the evaluation context may not be quite what the user expects.
    # In particular, it's equivalent to passing `eval("self", scope)` as `scope`.
    # This won't have an effect in most cases,
    # but if you're relying on local variables defined in the context of `scope`,
    # they won't work.
    #
    # @param scope [Binding, Proc, Object] The context in which the template is evaluated
    # @param locals [{Symbol => Object}] Local variables that will be made available
    #   to the template
    # @param block [#to_proc] A block that can be yielded to within the template
    # @return [String] The rendered template
    def render(scope = Object.new, locals = {}, &block)
      buffer = Haml::Buffer.new(scope.instance_variable_get('@haml_buffer'), options_for_buffer)

      if scope.is_a?(Binding) || scope.is_a?(Proc)
        scope_object = eval("self", scope)
        scope = scope_object.instance_eval{binding} if block_given?
      else
        scope_object = scope
        scope = scope_object.instance_eval{binding}
      end

      set_locals(locals.merge(:_hamlout => buffer, :_erbout => buffer.buffer), scope, scope_object)

      scope_object.instance_eval do
        extend Haml::Helpers
        @haml_buffer = buffer
      end

      eval(precompiled + ";" + precompiled_method_return_value,
        scope, @options[:filename], @options[:line])
    ensure
      # Get rid of the current buffer
      scope_object.instance_eval do
        @haml_buffer = buffer.upper
      end
    end
    alias_method :to_html, :render

    # Returns a proc that, when called,
    # renders the template and returns the result as a string.
    #
    # `scope` works the same as it does for render.
    #
    # The first argument of the returned proc is a hash of local variable names to values.
    # However, due to an unfortunate Ruby quirk,
    # the local variables which can be assigned must be pre-declared.
    # This is done with the `local_names` argument.
    # For example:
    #
    #     # This works
    #     Haml::Engine.new("%p= foo").render_proc(Object.new, :foo).call :foo => "Hello!"
    #       #=> "<p>Hello!</p>"
    #
    #     # This doesn't
    #     Haml::Engine.new("%p= foo").render_proc.call :foo => "Hello!"
    #       #=> NameError: undefined local variable or method `foo'
    #
    # The proc doesn't take a block; any yields in the template will fail.
    #
    # @param scope [Binding, Proc, Object] The context in which the template is evaluated
    # @param local_names [Array<Symbol>] The names of the locals that can be passed to the proc
    # @return [Proc] The proc that will run the template
    def render_proc(scope = Object.new, *local_names)
      if scope.is_a?(Binding) || scope.is_a?(Proc)
        scope_object = eval("self", scope)
      else
        scope_object = scope
        scope = scope_object.instance_eval{binding}
      end

      eval("Proc.new { |*_haml_locals| _haml_locals = _haml_locals[0] || {};" +
           precompiled_with_ambles(local_names) + "}\n", scope, @options[:filename], @options[:line])
    end

    # Defines a method on `object` with the given name
    # that renders the template and returns the result as a string.
    #
    # If `object` is a class or module,
    # the method will instead by defined as an instance method.
    # For example:
    #
    #     t = Time.now
    #     Haml::Engine.new("%p\n  Today's date is\n  .date= self.to_s").def_method(t, :render)
    #     t.render #=> "<p>\n  Today's date is\n  <div class='date'>Fri Nov 23 18:28:29 -0800 2007</div>\n</p>\n"
    #
    #     Haml::Engine.new(".upcased= upcase").def_method(String, :upcased_div)
    #     "foobar".upcased_div #=> "<div class='upcased'>FOOBAR</div>\n"
    #
    # The first argument of the defined method is a hash of local variable names to values.
    # However, due to an unfortunate Ruby quirk,
    # the local variables which can be assigned must be pre-declared.
    # This is done with the `local_names` argument.
    # For example:
    #
    #     # This works
    #     obj = Object.new
    #     Haml::Engine.new("%p= foo").def_method(obj, :render, :foo)
    #     obj.render(:foo => "Hello!") #=> "<p>Hello!</p>"
    #
    #     # This doesn't
    #     obj = Object.new
    #     Haml::Engine.new("%p= foo").def_method(obj, :render)
    #     obj.render(:foo => "Hello!") #=> NameError: undefined local variable or method `foo'
    #
    # Note that Haml modifies the evaluation context
    # (either the scope object or the `self` object of the scope binding).
    # It extends {Haml::Helpers}, and various instance variables are set
    # (all prefixed with `haml_`).
    #
    # @param object [Object, Module] The object on which to define the method
    # @param name [String, Symbol] The name of the method to define
    # @param local_names [Array<Symbol>] The names of the locals that can be passed to the proc
    def def_method(object, name, *local_names)
      method = object.is_a?(Module) ? :module_eval : :instance_eval

      object.send(method, "def #{name}(_haml_locals = {}); #{precompiled_with_ambles(local_names)}; end",
                  @options[:filename], @options[:line])
    end

    protected

    # Returns a subset of \{#options}: those that {Haml::Buffer} cares about.
    # All of the values here are such that when `#inspect` is called on the hash,
    # it can be `Kernel#eval`ed to get the same result back.
    #
    # See {file:HAML_REFERENCE.md#haml_options the Haml options documentation}.
    #
    # @return [{Symbol => Object}] The options hash
    def options_for_buffer
      {
        :autoclose => @options[:autoclose],
        :preserve => @options[:preserve],
        :attr_wrapper => @options[:attr_wrapper],
        :ugly => @options[:ugly],
        :format => @options[:format],
        :encoding => @options[:encoding],
        :escape_html => @options[:escape_html],
      }
    end

    private

    def set_locals(locals, scope, scope_object)
      scope_object.send(:instance_variable_set, '@_haml_locals', locals)
      set_locals = locals.keys.map { |k| "#{k} = @_haml_locals[#{k.inspect}]" }.join("\n")
      eval(set_locals, scope)
    end
  end
end
