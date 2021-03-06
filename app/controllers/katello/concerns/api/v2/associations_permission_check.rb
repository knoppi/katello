module Katello
  module Concerns
    module Api::V2::AssociationsPermissionCheck
      extend ActiveSupport::Concern

      # The purpose of this module is to protect a controller from a user creating or updating some association
      # when they do not have permissions to view the associated items.  An example would be adding random repository ids to
      # content view.
      # To support this, within the controller define a method such as:
      #     def filtered_associations
      #       {
      #         :component_ids => Katello::ContentViewVersion,
      #         :repository_ids => Katello::Repository
      #       }
      #     end
      # This assumes that the parameters are 'wrapped'.  So the above in the content_views_controller, actually looks at
      #  a subhash of 'content_view'

      included do
        before_action :check_association_ids, :only => [:create, :update]
      end

      def check_association_ids
        if filtered_associations
          wrapped_params = params[self._wrapper_options.name]
          find_param_arrays(wrapped_params).each do |key_path|
            if (model_class = filtered_associations.with_indifferent_access.dig(*key_path))
              param_ids = wrapped_params.dig(*key_path)
              filtered_ids = model_class.readable.where(:id => param_ids).pluck(:id)
              if (unfound_ids = param_ids_missing(param_ids, filtered_ids)).any?
                fail HttpErrors::NotFound, _("One or more ids (%{ids}) were not found for %{assoc}.  You may not have permissions to see them.") %
                    {ids: unfound_ids, assoc: key_path.last}
              end
            else
              fail _("Unfiltered params array: %s.") % key_path
            end
          end
        else
          Rails.logger.warn("#{self.class.name} may has unprotected associations, see associations_permission_check.rb for details.") if ENV['RAILS_ENV'] == 'development'
        end
      end

      def filtered_associations
        #should return {} when supported by all controllers
        nil
      end

      def param_ids_missing(param_ids, filtered_ids)
        param_ids.map(&:to_i).uniq - filtered_ids.map(&:to_i).uniq
      end

      #returns an array of list of keys pointing to an array in a params hash i.e.:
      # {"a"=> {"b" => [3]}}  =>  [["a", "b"]]
      def find_param_arrays(hash = params)
        list_of_paths = []
        hash.each do |key, value|
          if value.is_a?(ActionController::Parameters) || value.is_a?(Hash)
            list_of_paths += find_param_arrays(value).compact.map { |inner_keys| [key] + inner_keys }
          elsif value.is_a?(Array)
            list_of_paths << [key]
          end
        end
        list_of_paths.compact
      end
    end
  end
end
