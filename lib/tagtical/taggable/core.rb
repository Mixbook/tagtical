module Tagtical::Taggable
  module Core
    def self.included(base)
      base.class_eval do
        include Tagtical::Taggable::Core::InstanceMethods
        extend Tagtical::Taggable::Core::ClassMethods

        after_save :save_tags

        initialize_tagtical_core
      end
    end
    
    module ClassMethods
      def initialize_tagtical_core
        has_many :taggings, :as => :taggable, :dependent => :destroy, :include => :tag, :class_name => "Tagtical::Tagging"
        has_many :tags, :through => :taggings, :source => :tag, :class_name => "Tagtical::Tag",
                 :select => "#{Tagtical::Tag.table_name}.*, #{Tagtical::Tagging.table_name}.relevance" # include the relevance on the tags

        tag_types.each do |tag_type| # has_many :tags gets created here

          # Aryk: Instead of defined multiple associations for the different types of tags, I decided
          # to define the main associations (tags and taggings) and use AR scope's to build off of them.
          # This keeps your reflections cleaner.

          # In the case of the base tag type, it will just use the :tags association defined above.
          Tagtical::Tag.define_scope_for_type(tag_type)

          # If the tag_type is base? (type=="tag"), then we add additional functionality to the AR
          # has_many :tags.
          #
          #   taggable_model.tags(:scope => :children)
          #   taggable_model.tags <-- still works like normal has_many
          #   taggable_model.tags(true, :scope => :current) <-- reloads the tags association and appends scope for only current type.
          if tag_type.has_many_name==:tags
            define_method("tags_with_finder_type_options") do |*args|
              options = args.pop unless [true, false].include?(args.last) # true/false for has_many default functionality.
              scope = tags_without_finder_type_options(*args)
              options ? scope.tags(options) : scope
            end
            alias_method_chain :tags, :finder_type_options
          else
            delegate tag_type.has_many_name, :to => :tags
          end

          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def self.with_#{tag_type.pluralize}(*tags)
              options = tags.extract_options!
              tagged_with(tags.flatten, options.merge(:on => :#{tag_type}))
            end

            def #{tag_type}_list(scoping_options={})
              tag_list_on('#{tag_type}', scoping_options)
            end

            def #{tag_type}_list=(new_tags, scoping_options={})
              set_tag_list_on('#{tag_type}', new_tags, scoping_options)
            end
            alias set_#{tag_type}_list #{tag_type}_list=

            def all_#{tag_type.pluralize}_list(scoping_options={})
              all_tags_list_on('#{tag_type}', scoping_options)
            end
          RUBY

        end
      end
      
      def acts_as_taggable(*args)
        super(*args)
        initialize_tagtical_core
      end
      
      # all column names are necessary for PostgreSQL group clause
      def grouped_column_names_for(object)
        object.column_names.map { |column| "#{object.table_name}.#{column}" }.join(", ")
      end

      ##
      # Return a scope of objects that are tagged with the specified tags.
      #
      # @param tags The tags that we want to query for
      # @param [Hash] options A hash of options to alter you query:
      #                       * <tt>:exclude</tt> - if set to true, return objects that are *NOT* tagged with the specified tags
      #                       * <tt>:any</tt> - if set to true, return objects that are tagged with *ANY* of the specified tags
      #                       * <tt>:match_all</tt> - if set to true, return objects that are *ONLY* tagged with the specified tags
      #
      # Example:
      #   User.tagged_with("awesome", "cool")                     # Users that are tagged with awesome and cool
      #   User.tagged_with("awesome", "cool", :exclude => true)   # Users that are not tagged with awesome or cool
      #   User.tagged_with("awesome", "cool", :any => true)       # Users that are tagged with awesome or cool
      #   User.tagged_with("awesome", "cool", :match_all => true) # Users that are tagged with just awesome and cool
      #   User.tagged_with("awesome", "cool", :on => :skills)     # Users that are tagged with just awesome and cool on skills
      def tagged_with(tags, options = {})
        tag_list = Tagtical::TagList.from(tags)
        return scoped(:conditions => "1 = 0") if tag_list.empty? && !options[:exclude]

        joins = []
        conditions = []

        options[:on] ||= Tagtical::Tag::Type::BASE
        tag_type = Tagtical::Tag::Type.find(options.delete(:on))
        finder_type_condition_options = options.extract!(:scope)

        tag_table, tagging_table = Tagtical::Tag.table_name, Tagtical::Tagging.table_name

        if options.delete(:exclude)
          conditions << "#{table_name}.#{primary_key} NOT IN (" +
            "SELECT #{tagging_table}.taggable_id " +
            "FROM #{tagging_table} " +
            "JOIN #{tag_table} ON #{tagging_table}.tag_id = #{tag_table}.id AND #{tag_list.to_sql_conditions(:operator => "LIKE")} " +
            "WHERE #{tagging_table}.taggable_type = #{quote_value(base_class.name)})"

        elsif options.delete(:any)
          conditions << tag_list.to_sql_conditions(:operator => "LIKE")

          tagging_join  = " JOIN #{tagging_table}" +
            "   ON #{tagging_table}.taggable_id = #{table_name}.#{primary_key}" +
            "  AND #{tagging_table}.taggable_type = #{quote_value(base_class.name)}" +
            " JOIN #{tag_table}" +
            "   ON #{tagging_table}.tag_id = #{tag_table}.id"


          if (finder_condition = tag_type.finder_type_condition(finder_type_condition_options.merge(:sql => true))).present?
            conditions << finder_condition
          end

          select_clause = "DISTINCT #{table_name}.*" unless !tag_type.base? and tag_types.one?

          joins << tagging_join

        else
          tags_by_value = tag_type.scoping(finder_type_condition_options).where_any_like(tag_list).group_by(&:value)
          return scoped(:conditions => "1 = 0") unless tags_by_value.length == tag_list.length # allow for chaining

          # Create only one join per tag value.
          tags_by_value.each do |value, tags|
            tags.each do |tag|
              safe_tag = value.gsub(/[^a-zA-Z0-9]/, '')
              prefix   = "#{safe_tag}_#{rand(1024)}"

              taggings_alias = "#{undecorated_table_name}_taggings_#{prefix}"

              tagging_join  = "JOIN #{tagging_table} #{taggings_alias}" +
                "  ON #{taggings_alias}.taggable_id = #{table_name}.#{primary_key}" +
                " AND #{taggings_alias}.taggable_type = #{quote_value(base_class.name)}" +
                " AND #{sanitize_sql("#{taggings_alias}.tag_id" => tags.map(&:id))}"

              joins << tagging_join
            end
          end
        end

        taggings_alias, tags_alias = "#{undecorated_table_name}_taggings_group", "#{undecorated_table_name}_tags_group"

        if options.delete(:match_all)
          joins << "LEFT OUTER JOIN #{tagging_table} #{taggings_alias}" +
            "  ON #{taggings_alias}.taggable_id = #{table_name}.#{primary_key}" +
            " AND #{taggings_alias}.taggable_type = #{quote_value(base_class.name)}"


          group_columns = Tagtical::Tag.using_postgresql? ? grouped_column_names_for(self) : "#{table_name}.#{primary_key}"
          group = "#{group_columns} HAVING COUNT(#{taggings_alias}.taggable_id) = #{tag_list.size}"
        end
      
        scoped(:select     => select_clause,
               :joins      => joins.join(" "),
               :group      => group,
               :conditions => conditions.join(" AND "),
               :order      => options[:order],
               :readonly   => false)
      end

      def is_taggable?
        true
      end
    end    
    
    module InstanceMethods
      # all column names are necessary for PostgreSQL group clause
      def grouped_column_names_for(object)
        self.class.grouped_column_names_for(object)
      end

      def is_taggable?
        self.class.is_taggable?
      end

      def cached_tag_list_on(context)
        self[tag_type(context).tag_list_name(:cached)]
      end

      ##
      # model.set_tag_list_on("skill", ["kung fu", "karate"]) # will overwrite tags from inheriting tag classes
      # model.set_tag_list_on("skill", ["kung fu", "karate"], :scope => :==) # will not overwrite tags from inheriting tag classes
      def set_tag_list_on(context, new_list, scoping_options={})
        tag_list = Tagtical::TagList.from(new_list)
        cascade_set_tag_list!(tag_list, context, scoping_options)
        tag_list_cache_on(context)[scoping_options] = tag_list
      end

      def tag_list_on(context, scoping_options={})
        tag_list_cache_on(context)[scoping_options] ||= Tagtical::TagList.new(tags_on(context, scoping_options).map(&:value))
      end

      def tag_list_cache_on(context, prefix=nil)
        variable = tag_type(context).tag_list_ivar(prefix)
        instance_variable_get(variable) || instance_variable_set(variable, {})
      end

      def tag_types
        @tag_types ||= self.class.tag_types.dup
      end

      def all_tags_list_on(context, scoping_options={})
        tag_list_cache_on(context, :all)[scoping_options] ||= Tagtical::TagList.new(all_tags_on(context, scoping_options).map(&:value)).freeze
      end

      ##
      # Returns all tags of a given context
      def all_tags_on(context, scoping_options={})
        scope = tag_scope(context, scoping_options)
        if Tagtical::Tag.using_postgresql?
          group_columns = grouped_column_names_for(Tagtical::Tag)
          scope = scope.order("max(#{Tagtical::Tagging.table_name}.created_at)").group(group_columns)
        else
          scope = scope.group("#{Tagtical::Tag.table_name}.#{Tagtical::Tag.primary_key}")
        end
        scope.all
      end

      ##
      # Returns all tags that aren't owned.
      def tags_on(context, scoping_options={})
        tag_scope(context, scoping_options).where("#{Tagtical::Tagging.table_name}.tagger_id IS NULL").all
      end

      def reload(*args)
        tag_types.each do |tag_type|
          instance_variable_set(tag_type.tag_list_ivar, nil)
          instance_variable_set(tag_type.tag_list_ivar(:all), nil)
        end
      
        super(*args)
      end

      def save_tags
        # Do the classes from top to bottom. We want the list from "tag" to run before "sub_tag" runs.
        # Otherwise, we will end up removing taggings from "sub_tag" since they aren't on "tag'.
        tag_types.sort_by(&:active_record_sti_level).each do |tag_type|
          (tag_list_cache_on(tag_type) || {}).each do |scoping_options, tag_list|
            tag_list = tag_list.uniq

            # Find existing tags or create non-existing tags:
            tag_value_lookup = tag_type.scoping { find_or_create_tags(tag_list) }
            tags = tag_value_lookup.keys

            options = {:scope => [:current, :children]}.update(scoping_options)
            options[:scope] = Array(options[:scope]) + [:parents] # add in the parents because we need them later on down.

            current_tags = tags_on(tag_type, options)
            old_tags     = current_tags - tags
            new_tags     = tags         - current_tags

            unowned_taggings = taggings.where(:tagger_id => nil)

            # If relevances are specified on current tags, make sure to update those
            tags_requiring_relevance_update = tag_value_lookup.map { |tag, value| tag if !value.relevance.nil? }.compact & current_tags
            if tags_requiring_relevance_update.present? && (update_taggings = unowned_taggings.find_all_by_tag_id(tags_requiring_relevance_update)).present?
              update_taggings.each { |tagging| tagging.update_attribute(:relevance, tag_value_lookup[tagging.tag].relevance) }
            end

            # Find and remove old taggings:
            if old_tags.present? && (old_taggings = unowned_taggings.find_all_by_tag_id(old_tags)).present?
              old_taggings.reject! do |tagging|
                if tagging.tag.class > tag_type.klass! # parent of current tag type/class, make sure not to remove these taggings.
                  update_tagging_with_inherited_tag!(tagging, new_tags, tag_value_lookup)
                  true
                end
              end
              Tagtical::Tagging.destroy_all :id => old_taggings.map(&:id) # Destroy old taggings:
            end

            new_tags.each do |tag|
              taggings.create!(:tag_id => tag.id, :taggable => self, :relevance => tag_value_lookup[tag].relevance) # Create new taggings:
            end
          end
        end

        true
      end

      private

      def tag_scope(input, options={})
        tags.where(tag_type(input).finder_type_condition(options))
      end

      # Returns the tag type for the given context and adds any new types tag_types array on this instance.
      def tag_type(input)
        (@tag_type ||= {})[input] ||= Tagtical::Tag::Type[input].tap do |tag_type|
          tag_types << tag_type unless tag_types.include?(tag_type)
        end
      end

      # Lets say tag class A inherits from B and B has a tag with value "foo". If we tag A with value "foo",
      # we want B to have only one instance of "foo" and that tag should be an instance of A (a subclass of B).
      def update_tagging_with_inherited_tag!(tagging, tags, tag_value_lookup)
        if tags.present? && (tag = Tagtical::Tag.send(:detect_comparable, tags, tagging.tag.value))
          tagging.update_attributes!(:tag => tag, :relevance => tag_value_lookup[tag].relevance)
          tags.delete(tag)
        end
      end

      # If cascade tag types are specified, it will attempt to look at Tag subclasses with
      # possible_values and try to set those tag_lists with values from the possible_values list.
      def cascade_set_tag_list!(tag_list, context, scoping_options)
        if (cascade = scoping_options.delete(:cascade)) && (tag_type = tag_type(context)).klass
          tag_types = cascade==true ? self.tag_types : Tagtical::Tag::Type[Array(cascade)]
          tag_types.each do |t|
            if t.klass && t.klass <= tag_type.klass && t.klass.possible_values
              new_tag_list = Tagtical::TagList.new
              tag_list.reject! do |elm|
                if value = t.klass.detect_possible_value(elm)
                  new_tag_list << value
                  true
                end
              end
              tag_list_cache_on(t)[scoping_options.merge(:scope => :==)] = new_tag_list if !new_tag_list.empty?
            end
          end
        end
      end

    end
  end
end
