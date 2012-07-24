module Tagtical
  module TagGroup

    def acts_as_tag_group
      extend ClassMethods
    end

    module ClassMethods
      def has_many_through_tags(association_id)
        define_method(association_id) do
          klass = association_id.to_s.singularize.camelize.constantize
          klass.
            joins(:taggings).
            where("#{Tagtical::Tagging.table_name}.`tag_id` IN (?)", taggings.map(&:tag_id)).
            group("#{klass.table_name}.id").having(["count(#{klass.table_name}.id) = ?", taggings.count])
        end
      end

      def belongs_to_through_tags(association_id)
        define_method(association_id) do
          klass = association_id.to_s.singularize.camelize.constantize
          klass.
            joins(
              "LEFT JOIN #{Tagtical::Tagging.table_name} AS t1 " +
              "ON t1.taggable_id = #{klass.table_name}.id AND t1.taggable_type = '#{klass}'"
            ).
            joins(
              "LEFT JOIN #{Tagtical::Tagging.table_name} AS t2 " +
              "ON t2.tag_id = t1.tag_id AND t2.taggable_type = '#{self.class}' AND t2.taggable_id = #{id}"
            ).
            group("#{klass.table_name}.id").
            having("COUNT(t2.tag_id) = COUNT(#{klass.table_name}.id)")
        end
      end

    end
  end
end
