module Tagtical
  module Taggable
    module TagGroup

      def has_many_through_tags(association_id, type = :subset, options = {})
        case type
        when :subset then has_many_through_tags_subset(association_id, options)
        when :superset then has_many_through_tags_superset(association_id, options)
        else raise "Wrong association type, should be :subset or :superset"
        end
        after_save { instance_variable_set("@#{association_id}", nil) }
      end

      private

        def has_many_through_tags_superset(association_id, options)
          define_method(association_id) do
            result = instance_variable_get("@#{association_id}") || begin
              klass = (options[:class_name] || association_id.to_s.singularize.camelize).constantize
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
            instance_variable_set("@#{association_id}", result)
            result
          end
        end

        def has_many_through_tags_subset(association_id, options)
          define_method(association_id) do
            result = instance_variable_get("@#{association_id}") || begin
              klass = (options[:class_name] || association_id.to_s.singularize.camelize).constantize
              klass.
                joins(:taggings).
                where("#{Tagtical::Tagging.table_name}.`tag_id` IN (?)", taggings.map(&:tag_id)).
                group("#{klass.table_name}.id").having(["count(#{klass.table_name}.id) = ?", taggings.count])
            end
            instance_variable_set("@#{association_id}", result)
            result
          end
        end
    end
  end
end
