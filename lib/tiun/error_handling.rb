module Tiun
   module ErrorHandling
      extend ActiveSupport::Concern

      STATUSES = Rack::Utils::SYMBOL_TO_STATUS_CODE.dup
      EXCEPTIONS = Hash.new { |this, key| this[key] = :internal_server_error }.merge(
         "ActionController::ParameterMissing" => :internal_server_error, # parameter missing
         "ActionController::InvalidAuthenticityToken" => :unauthorized,
         "ActiveRecord::RecordNotUnique" => :unprocessable_entity,
         "ActiveRecord::RecordInvalid" => :unprocessable_entity,
         "ActiveRecord::RecordNotSaved" => :unprocessable_entity,
         "ActiveRecord::RecordNotFound" => :not_found,
         "ActionView::MissingTemplate" => :internal_server_error, # missing template
         "CarrierWave::IntegrityError" => :unprocessable_entity,
         "Tiun::Base::InvalidParamNameError" => :not_found,
         "Tiun::Base::OutOfRangeError" => :range_not_satisfiable, # out of range
         "Tiun::Model::Account::InvalidPasswordError" => :unauthorized,
         "Tiun::Model::Auth::InvalidTokenError" => :unauthorized, # not authenticated
         "Tiun::Policy::NotAuthorizedError" => :forbidden, # not authorized
         "Tiun::Auth::Controller::UnauthorizedError" => :forbidden,
         "Tiun::Auth::Controller::UnauthenticatedError" => :unauthorized,
         "Tiun::Auth::Controller::NoTokenError" => :not_found,
         "Tiun::Auth::Controller::InvalidTokenError" => :not_found)

      included do
         extend self::SingularMethods

         rescue_from Exception, with: :render_exception
      end

      def code_for e
         exceptions =
            Tiun::ErrorHandling::EXCEPTIONS.merge(
               self.class.respond_to?(:proceed_list) ? self.class.proceed_list : {})

         exceptions[e.class.to_s]
      end

      def render_exception e
         code = code_for(e)
         args = params.permit(*permitted_filter).to_h rescue {}
         res = { status: code, json: {} }

         res[:json][:args] = args if args.present?
         res[:json][:status] = STATUSES[code] if STATUSES[code].to_i >= 400

         if errors = @object && @object.errors.any? && @object.errors.to_a
            res[:json][:errors] = errors
         end

         if e && res[:json][:status] >= 500
            /`(?<method>(?:with_(?<rela>\w+)|[^']*))'/ =~ caller.grep(%r{tiun/base})[1]
            trace = "[#{e.class}]{#{method}}> #{e.message} \n\t #{e.backtrace.join("\n\t")}"

            logger.error(trace) if defined?(logger)

            # res[:json][:trace] = trace
         end

         args.present? || errors.present? ? render(**res) : head(code)
      end

      module SingularMethods
         def proceed_list
            @proceed_list ||= {}
         end

         def proceed_when *exceptions, with: nil
            exceptions.each do |exception|
               proceed_list[exception] = with
            end if with
         end
      end
   end
end
