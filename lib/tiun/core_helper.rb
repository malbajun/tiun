require 'action_view'

module ::Tiun::CoreHelper
   include ::ActionView::Helpers::TagHelper

   def react_component name, props = {}, options = {}, &block
      html_options = options.reverse_merge(data: {
         react_class: name,
         react_props: (props.is_a?(String) ? props : props.to_json)
      })
      content_tag(:div, '', html_options, &block)
   end

   def current_user_data
      @current_user&.jsonize(only:
         ["id", "last_login_at", "last_active_at", "default_name", "refresh_token", "session_token",
         "accounts" => %w(id no type),
         "user_names" => %w(id kind way usage source main nomen_id name),
         "descriptions" => %w(id language_code alphabeth_code type text)])
   end
end

CoreHelper = ::Tiun::CoreHelper
