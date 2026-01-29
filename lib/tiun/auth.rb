# cuccon auth methods for all controllers
module Tiun::Auth
   extend ActiveSupport::Concern

   included do
      before_action :authenticate_user
      before_action :authorize!, if: -> { current_user }
   end

   def current_user
      @current_user ||= session["user"] && user
   end

   def user context = auth_context
      @user ||= User.with_user_names(context)
                    .with_descriptions(context)
                    .with_accounts(context)
                    .where(id: session["user"]&.[]("id"))
                    .first
   end

   def authenticate_user
      current_user
   end

   def model_name
      @_model_name ||= self.class.to_s.gsub(/.*::/, "").gsub("Controller", "").singularize
   end

   def model
      @_model ||= model_name.constantize
   rescue NameError
      User
   end

   def tiun_context
      self.class.instance_variable_get(:@context) || {}
   end

   def action_context
      tiun_context[action_name].find{ |x| x["context_name"] == params["context_name"] } || {}.to_os
   end

   def get_properties for_object = nil
      @get_properties ||=
         if k = action_context.kind
            Tiun.type_attributes_for(k)
         else
            case for_object
            when ActiveRecord::Reflection, ActiveRecord::Associations, ActiveRecord::Scoping, ActiveRecord::Base
               for_object.model
            when Array
               for_object.find { |x| x.respond_to?(:attribute_types) } ||
                  for_object.find { |x| x.class.respond_to?(:attribute_types) }.class
            when Hash
               for_object.values.find { |x| x.respond_to?(:attribute_types) } ||
                  for_object.values.find { |x| x.class.respond_to?(:attribute_types) }.class
            when NilClass
               model
            else
               for_object
            end.attribute_types.keys
         end
   end

   def auth_context
      @auth_context ||= { except: supplement_names, locales: locales }
   end

   def context
      @context ||= { except: supplement_names, locales: locales }
   end

   def locales
      @locales ||= [I18n.locale]
   end

   def supplement_names
      %i(created_at updated_at tsv)
   end

   def serialize object, context = self.context
      object.as_json(context.merge(only: get_properties(object)))
   end

   def subject
      action_name == 'index' ? objects : action_name == 'create' ? new_object : object
   end

   def policy
      @_policy ||= "#{model_name}Policy".constantize
   rescue NameError
      Tiun::Policy::Default
   end

   def authorize!
      pol = policy.new(current_user, subject)

      if pol.respond_to?(action_name + "?") && !pol.send(action_name + "?") ||
          pol.respond_to?(:match?) && self.respond_to?(:allowing_permission) && !pol.match?(allowing_permission)

         raise Tiun::Policy::NotAuthorizedError, "not allowed to perform '#{action_name}' this with '#{@object.inspect}'"
      end
   end
end

Auth = Tiun::Auth
