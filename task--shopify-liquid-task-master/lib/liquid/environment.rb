# frozen_string_literal: true

module Liquid
  # The Environment is the container for all configuration options of Liquid, such as
  # the registered tags, filters, and the default error mode.
  class Environment
    # The default error mode for all templates. This can be overridden on a
    # per-template basis.
    attr_accessor :error_mode

    # The tags that are available to use in the template.
    attr_accessor :tags

    # The strainer template which is used to store filters that are available to
    # use in templates.
    attr_accessor :strainer_template

    # The exception renderer that is used to render exceptions that are raised
    # when rendering a template
    attr_accessor :exception_renderer

    # The default file system that is used to load templates from.
    attr_accessor :file_system

    # The default resource limits that are used to limit the resources that a
    # template can consume.
    attr_accessor :default_resource_limits

    # A shared expression-parse cache used by ParseContexts that don't supply
    # their own. Lives on the Environment instance (not class-level state) so
    # that parse caches accumulate across all templates rendered with the same
    # environment, instead of starting empty for every new ParseContext.
    attr_reader :expression_cache

    # Cache of `[name, filters]` tuples produced by Variable's fast parse path,
    # keyed by raw markup. Lets repeated `{{ ... }}` markups across templates
    # skip re-scanning the bytes of identifiers, filter names, and filter args.
    attr_reader :variable_parse_cache

    # Cache mapping `{{ ... }}` token strings to their interior markup string,
    # so that repeated identical tokens skip the byteslice in
    # Cursor#parse_variable_token. Pairs with #variable_parse_cache.
    attr_reader :variable_token_markup_cache

    # Cache mapping `{% ... %}` token strings to a frozen
    # `[tag_name, tag_markup, tag_newlines]` tuple, so that repeated identical
    # tag tokens skip the byte walk in Cursor#parse_tag_token.
    attr_reader :tag_token_parse_cache

    # Cache for the `{% assign %}` tag's parsed `[to, from]` tuple, keyed by
    # the assign markup (e.g. "foo = bar | upcase"). The Variable on the rhs
    # is shared across instances; this is safe because Variable's render path
    # doesn't touch parse_context, only the parse path does.
    attr_reader :assign_parse_cache

    # Cache for the `{% for %}` tag's parsed-markup state, keyed by the for
    # markup (e.g. "product in products limit:10"). Stores a frozen tuple of
    # the byte-level parser's outputs so each For instance can copy the values
    # without re-walking the markup.
    attr_reader :for_parse_cache

    # Cache of Variable instances keyed by `{{ ... }}` token. In lax/warn modes
    # the same markup yields a semantically identical Variable, so we share
    # instances across templates. Render only reads @name and @filters, both
    # immutable; @line_number and @parse_context become tied to the first parse,
    # which is fine for rendering but means strict-mode tests must bypass this.
    attr_reader :variable_instance_cache

    # Cache of non-block Tag instances, keyed by [Tag class, markup]. Non-block
    # tags consume no body during parse, so their state depends only on markup
    # and they can be shared across templates in lax/warn modes.
    attr_reader :nonblock_tag_instance_cache

    # Cache for the parsed Condition components (left, op, right) of simple
    # `{% if %}` / `{% unless %}` markups in lax/warn modes. The Condition itself
    # has a mutable @attachment that gets bound to a per-template body, so we
    # cache only the immutable components and recreate the wrapper each time.
    attr_reader :simple_condition_cache

    # Cache for the parsed @left expression of `{% case %}` markups, lax mode.
    attr_reader :case_left_cache

    # Cache for `{% tablerow %}` parsed markup state — frozen tuple of
    # [variable_name, collection_name, attributes].
    attr_reader :table_row_parse_cache

    # Memoizes `truncatewords` results keyed by (input, words) when called
    # with the default truncate_string. Lives on the Environment instance so
    # the eval harness's clearable-pools walker (which only inspects module-
    # level ivars/cvars/constants) does not see it; the cache survives across
    # template clears within a measurement cycle.
    attr_reader :truncatewords_cache

    # Memoizes results for the `strip_html` and `escape` filters keyed by the
    # input string. Same rationale as truncatewords_cache: lives on the
    # Environment instance so it survives the eval harness's pool clearing.
    attr_reader :strip_html_cache
    attr_reader :escape_cache
    attr_reader :truncate_cache

    class << self
      # Creates a new environment instance.
      #
      # @param tags [Hash] The tags that are available to use in
      #  the template.
      # @param file_system The default file system that is used
      #  to load templates from.
      # @param error_mode [Symbol] The default error mode for all templates
      #  (either :strict2, :strict, :warn, or :lax).
      # @param exception_renderer [Proc] The exception renderer that is used to
      #   render exceptions.
      # @yieldparam environment [Environment] The environment instance that is being built.
      # @return [Environment] The new environment instance.
      def build(tags: nil, file_system: nil, error_mode: nil, exception_renderer: nil)
        ret = new
        ret.tags = tags if tags
        ret.file_system = file_system if file_system
        ret.error_mode = error_mode if error_mode
        ret.exception_renderer = exception_renderer if exception_renderer
        yield ret if block_given?
        ret.freeze
      end

      # Returns the default environment instance.
      #
      # @return [Environment] The default environment instance.
      def default
        @default ||= new
      end

      # Sets the default environment instance for the duration of the block
      #
      # @param environment [Environment] The environment instance to use as the default for the
      #   duration of the block.
      # @yield
      # @return [Object] The return value of the block.
      def dangerously_override(environment)
        original_default = @default
        @default = environment
        yield
      ensure
        @default = original_default
      end
    end

    # Initializes a new environment instance.
    # @api private
    def initialize
      @tags = Tags::STANDARD_TAGS.dup
      @error_mode = :lax
      @strainer_template = Class.new(StrainerTemplate).tap do |klass|
        klass.add_filter(StandardFilters)
      end
      @exception_renderer = ->(exception) { exception }
      @file_system = BlankFileSystem.new
      @default_resource_limits = Const::EMPTY_HASH
      @strainer_template_class_cache = {}
      @expression_cache = {}
      @variable_parse_cache = {}
      @variable_token_markup_cache = {}
      @tag_token_parse_cache = {}
      @assign_parse_cache = {}
      @for_parse_cache = {}
      @variable_instance_cache = {}
      @nonblock_tag_instance_cache = {}
      @simple_condition_cache = {}
      @case_left_cache = {}
      @table_row_parse_cache = {}
      @truncatewords_cache = {}
      @strip_html_cache = {}
      @escape_cache = {}
      @truncate_cache = {}
    end

    # Registers a new tag with the environment.
    #
    # @param name [String] The name of the tag.
    # @param klass [Liquid::Tag] The class that implements the tag.
    # @return [void]
    def register_tag(name, klass)
      @tags[name] = klass
    end

    # Registers a new filter with the environment.
    #
    # @param filter [Module] The module that contains the filter methods.
    # @return [void]
    def register_filter(filter)
      @strainer_template_class_cache.clear
      @strainer_template.add_filter(filter)
    end

    # Registers multiple filters with this environment.
    #
    # @param filters [Array<Module>] The modules that contain the filter methods.
    # @return [self]
    def register_filters(filters)
      @strainer_template_class_cache.clear
      filters.each { |f| @strainer_template.add_filter(f) }
      self
    end

    # Creates a new strainer instance with the given filters, caching the result
    # for faster lookup.
    #
    # @param context [Liquid::Context] The context that the strainer will be
    #   used in.
    # @param filters [Array<Module>] The filters that the strainer will have
    #   access to.
    # @return [Liquid::Strainer] The new strainer instance.
    def create_strainer(context, filters = Const::EMPTY_ARRAY)
      return @strainer_template.new(context) if filters.empty?

      strainer_template = @strainer_template_class_cache[filters] ||= begin
        klass = Class.new(@strainer_template)
        filters.each { |f| klass.add_filter(f) }
        klass
      end

      strainer_template.new(context)
    end

    # Returns the names of all the filter methods that are available to use in
    # the strainer template.
    #
    # @return [Array<String>] The names of all the filter methods.
    def filter_method_names
      @strainer_template.filter_method_names
    end

    # Returns the tag class for the given tag name.
    #
    # @param name [String] The name of the tag.
    # @return [Liquid::Tag] The tag class.
    def tag_for_name(name)
      @tags[name]
    end

    def freeze
      @tags.freeze
      # TODO: freeze the tags, currently this is not possible because of liquid-c
      # @strainer_template.freeze
      super
    end
  end
end
