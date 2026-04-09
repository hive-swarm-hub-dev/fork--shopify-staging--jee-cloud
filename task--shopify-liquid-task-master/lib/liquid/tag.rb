# frozen_string_literal: true

require 'liquid/tag/disabler'
require 'liquid/tag/disableable'

module Liquid
  class Tag
    attr_reader :nodelist, :tag_name, :line_number, :parse_context
    alias_method :options, :parse_context
    include ParserSwitching

    class << self
      def parse(tag_name, markup, tokenizer, parse_context)
        # Non-block tag instance cache. Non-block tags consume no body during
        # parse, so their entire state is determined by markup. In lax/warn
        # modes we share instances across templates via a per-Environment hash.
        # Block subclasses bypass this because they each carry per-template body
        # state in @nodelist (and the body itself differs across templates).
        if !(self < Block)
          error_mode = parse_context.error_mode
          if error_mode != :strict && error_mode != :strict2 && error_mode != :rigid
            cache = parse_context.environment.nonblock_tag_instance_cache
            key = [self, markup]
            cached = cache[key]
            return cached if cached
            warnings_before = parse_context.warnings.size
            tag = new(tag_name, markup, parse_context)
            tag.parse(tokenizer)
            cache[key] = tag if parse_context.warnings.size == warnings_before
            return tag
          end
        end
        tag = new(tag_name, markup, parse_context)
        tag.parse(tokenizer)
        tag
      end

      def disable_tags(*tag_names)
        tag_names += disabled_tags
        define_singleton_method(:disabled_tags) { tag_names }
        prepend(Disabler)
      end

      private :new

      protected

      def disabled_tags
        []
      end
    end

    def initialize(tag_name, markup, parse_context)
      @tag_name      = tag_name
      @markup        = markup
      @parse_context = parse_context
      @line_number   = parse_context.line_number
    end

    def parse(_tokens)
    end

    def raw
      "#{@tag_name} #{@markup}"
    end

    def name
      self.class.name.downcase
    end

    def render(_context)
      ''
    end

    # For backwards compatibility with custom tags. In a future release, the semantics
    # of the `render_to_output_buffer` method will become the default and the `render`
    # method will be removed.
    def render_to_output_buffer(context, output)
      render_result = render(context)
      output << render_result if render_result
      output
    end

    def blank?
      false
    end

    private

    def safe_parse_expression(parser)
      parse_context.safe_parse_expression(parser)
    end

    def parse_expression(markup, safe: false)
      parse_context.parse_expression(markup, safe: safe)
    end
  end
end
