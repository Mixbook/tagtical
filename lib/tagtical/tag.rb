module Tagtical
  class Tag < ::ActiveRecord::Base
    
    attr_accessible :value

    ### ASSOCIATIONS:

    has_many :taggings, :dependent => :destroy, :class_name => 'Tagtical::Tagging'

    ### VALIDATIONS:
    
    validates :value, :uniqueness => {:scope => :type}, :presence => true # type is not required, it can be blank

    ## POSSIBLE_VALUES SUPPORT:

    class_attribute :possible_values
    validate :validate_possible_values
    
    self.store_full_sti_class = false

    ### CLASS METHODS:

    class << self

      def where_any(list, options={})
        char = "%" if options[:wildcard]
        operator = options[:case_insensitive] || options[:wildcard] ?
          (using_postgresql? ? 'ILIKE' : 'LIKE') :
          "="
        conditions = Array(list).map { |tag| ["value #{operator} ?", "#{char}#{tag.to_s}#{char}"] }
        where(conditions.size==1 ? conditions.first : conditions.map { |c| sanitize_sql(c) }.join(" OR "))
      end

      def using_postgresql?
        connection.adapter_name=='PostgreSQL'
      end

      # Use this for case insensitive 
      def where_any_like(list, options={})
        where_any(list, options.update(:case_insensitive => true))
      end

      ### CLASS METHODS:

      def find_or_create_with_like_by_value!(value)
        where_any_like(value).first || create!(:value => value)
      end

      # Method used to ensure list of tags for the given Tag class.
      # Returns a hash with the key being the value from the tag list and the value being the saved tag.
      def find_or_create_tags(*tag_list)
        tag_list = [tag_list].flatten
        return {} if tag_list.empty?

        existing_tags  = where_any_like(tag_list).all
        tag_list.each_with_object({}) do |value, tag_lookup|
          tag_lookup[detect_comparable(existing_tags, value) || create!(:value => value)] = value
        end
      end

      def sti_name
        return @sti_name if instance_variable_defined?(:@sti_name)
        @sti_name = Tagtical::Tag==self ? nil : Type.new(name.demodulize)
      end

      protected

      def compute_type(type_name)
        @@compute_type ||= {}
        # super is required when it gets called from a reflection.
        @@compute_type[type_name] || super
      rescue Exception => e
        @@compute_type[type_name] = Type.new(type_name).klass!
      end

      private
      
      # Checks to see if a tags value is present in a set of tags and returns that tag.
      def detect_comparable(tags, value)
        value = comparable_value(value)
        tags.detect { |tag| comparable_value(tag.value) == value }
      end

      def comparable_value(str)
        RUBY_VERSION >= "1.9" ? str.downcase : str.mb_chars.downcase
      end

    end

    ### INSTANCE METHODS:

    def ==(object)
      super || (object.is_a?(self.class) && value == object.value)
    end

    def relevance
      (v = self["relevance"]) && v.to_f
    end

    # Try to sort by the relevance if provided.
    def <=>(tag)
      if (r1 = relevance) && (r2 = tag.relevance)
        r1 <=> r2
      else
        value <=> tag.value
      end
    end

    def to_s
      value
    end

    # Overwrite these methods to provide your own storage mechanism for a tag.
    def load_value(value) value end
    def dump_value(value) value end

    def value
      @value ||= load_value(self[:value])
    end

    def value=(value)
      @value = nil
      self[:value] = dump_value(value)
    end

    # We return nil if we are *not* an STI class.
    def type
      type = self[:type]
      type && Type[type]
    end

    def count
      self[:count].to_i
    end

    private

    def validate_possible_values
      if possible_values && !possible_values.include?(value)
        errors.add(:value, %{Value "#{value}" not found in list: #{possible_values.inspect}})
      end
    end

    class Type < String

      # "tag" should always correspond with demodulize name of the base Tag class (ie Tagtical::Tag).
      BASE = "tag".freeze

      # Default to simply "tag", if none is provided. This will return Tagtical::Tag on calls to #klass
      def initialize(arg)
        super(arg.to_s.singularize.underscore.gsub(/_tag$/, ''))
      end

      class << self
        def find(input)
          return input.map { |c| self[c] } if input.is_a?(Array)
          input.is_a?(self) ? input : new(input)
        end
        alias :[] :find
      end

      # Leverages current type_condition logic from ActiveRecord while also allowing for type conditions
      # when no Tag subclass is defined. Also, it builds the type condition for STI inheritance.
      #
      # Options:
      #   <tt>parents</tt> - Set to true to include the parents type condition. Set to :only to return a scope with only the parent type condition.
      #   <tt>sql</tt> - Set to true to return sql string. Set to :append to return a sql string which can be appended as a condition.
      #
      def finder_type_condition(options={})
        sti_column = Tagtical::Tag.arel_table[Tagtical::Tag.inheritance_column]
        condition = if klass
            klass.send(:type_condition) if klass.finder_needs_type_condition?
          else # else do a match only the type itself (ie tags.type = "special")
            sti_column.eq(self)
          end unless options[:parents]==:only
        if options[:parents] && klass # include searches up the STI chain
          parent_class = klass.superclass
          while parent_class <= Tagtical::Tag
            type_condition = sti_column.eq(parent_class.sti_name)
            condition = condition ? condition.or(type_condition) : type_condition
            parent_class = parent_class.superclass
          end
        end
        if condition && options[:sql]
          condition = condition.to_sql
          condition.insert(0, " AND ") if options[:sql]==:append
        end
        condition
      end

      def scoping
        if finder_type_condition
          Tagtical::Tag.send(:with_scope, :find => Tagtical::Tag.where(finder_type_condition), :create => {:type => self}) do
            yield
          end
        else
          yield
        end
      end

      # Creates AR Relation Object to query
      def scoped(method_name=nil, *args, &block)
        if method_name # by passing in the method_name, we can create a scoping with a :create scope
          scoping { Tagtical::Tag.send(method_name, *args, &block) }
        else
          Tagtical::Tag.send(*(finder_type_condition ? [:where, finder_type_condition] : :unscoped))
        end
      end

      # Return the Tag subclass
      def klass
        instance_variable_get(:@klass) || instance_variable_set(:@klass, find_tag_class)
      end

      # Return the Tag class or return top-level
      def klass!
        klass || Tagtical::Tag
      end

      def has_many_name
        pluralize.to_sym
      end
      alias scope_name has_many_name

      def base?
        !!klass && klass.descends_from_active_record?
      end

      def ==(val)
        super(self.class[val])
      end

      def tag_list_name(prefix=nil)
        prefix = prefix.to_s.dup
        prefix << "_" unless prefix.blank?
        "#{prefix}#{self}_list"
      end

      def tag_list_ivar(*args)
        "@#{tag_list_name(*args)}"
      end

      # Returns the level from which it extends from Tagtical::Tag
      def active_record_sti_level
        @active_record_sti_level ||= begin
          count, current_class = 0, klass!
          while !current_class.descends_from_active_record?
            current_class = current_class.superclass
            count += 1
          end
          count
        end
      end

      private

      # Returns an array of potential class names for this specific type.
      def derive_class_candidates
        [].tap do |arr|
          [classify, "#{classify}Tag"].each do |name| # support Interest and InterestTag class names.
            "Tagtical::Tag".tap do |longest_candidate|
              longest_candidate << "::#{name}" unless name=="Tag"
            end.scan(/^|::/) { arr << $' } # Klass, Tag::Klass, Tagtical::Tag::Klass
          end
        end
      end

      def find_tag_class
        candidates = derive_class_candidates

        # Attempt to find the preloaded class instead of having to do NameError catching below.
        candidates.each do |candidate|
          constants = ActiveSupport::Dependencies::Reference.send(:class_variable_get, :@@constants)
          if constants.key?(candidate) && (constant = constants[candidate]) <= Tagtical::Tag # must check for key first, do not want to trigger default proc.
            return constant
          end
        end

        # Logic comes from ActiveRecord::Base#compute_type.
        candidates.each do |candidate|
          begin
            constant = ActiveSupport::Dependencies.constantize(candidate)
            return constant if candidate == constant.to_s && constant <= Tagtical::Tag
          rescue NameError => e
            # We don't want to swallow NoMethodError < NameError errors
            raise e unless e.instance_of?(NameError)
          rescue ArgumentError
          end
        end

        nil
      end
    end

  end
end
