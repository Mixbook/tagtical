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
            group("#{klass.table_name}.id").having("count(#{klass.table_name}.id) = ?", taggings.count)
        end
      end
    end
  end
end
