module Tiun::ErrorHandling
   extend ActiveSupport::Concern

   included do
      rescue_from Exception, with: :server_error
      rescue_from ActionView::MissingTemplate, with: :missing_template
      rescue_from ActionController::ParameterMissing, with: :parameter_missing
      rescue_from ActiveRecord::RecordNotUnique,
                  ActiveRecord::RecordInvalid,
                  ActiveRecord::RecordNotSaved,
                  CarrierWave::IntegrityError, with: :unprocessable_entity
      rescue_from Tiun::Base::OutOfRangeError, with: :out_of_range
      rescue_from Tiun::Model::Auth::InvalidTokenError, with: :unauthenticated
      rescue_from Tiun::Policy::NotAuthorizedError, with: :unauthorized
   end

   def unauthenticated _e
      render_code :unauthorized
   end

   def unauthorized _e
      render_code :forbidden
   end

   def not_found _e
      render_code :not_found
   end

   def out_of_range _e
      render_code :range_not_satisfiable
   end

   def unprocessable_entity _e
      render_code :unprocessable_entity
   end

   def parameter_missing e
      render_code :internal_server_error, e
   end

   def missing_template e
      render_code :internal_server_error, e
   end

   def server_error e
      render_code :internal_server_error, e
   end

   def render_code code, e = nil
      args = params.permit(*permitted_filter).to_h rescue {}
      res = { status: code, json: {} }

      res[:json][:args] = args if args.present?

      if errors = @object && @object.errors.any? && @object.errors.to_a
         res[:json][:errors] = errors
      end

      if e
         /`(?<method>(?:with_(?<rela>\w+)|[^']*))'/ =~ caller.grep(%r{tiun/base})[1]
         trace = "[#{e.class}]{#{method}}> #{e.message} \n\t #{e.backtrace.join("\n\t")}"

         res[:json][:trace] = trace
      end

      args.present? || errors.present? ? render(**res) : head(code)
   end
end

ErrorHandling = Tiun::ErrorHandling
