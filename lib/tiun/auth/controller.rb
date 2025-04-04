require 'active_support'
require 'tiun/auth'

module Tiun::Auth::Controller
   class NoTokenError < StandardError; end
   class InvalidTokenError < StandardError; end
   class UnauthorizedError < StandardError; end

   extend ActiveSupport::Concern

   included do
      include ActionController::RequestForgeryProtection
      include Tiun::Auth

      protect_from_forgery only: :create, with: :exception, prepend: true

      before_action :set_languages
      before_action :fetch_token, only: %i(update show destroy)
      after_action :obsolete_token, only: %i(update show destroy)
      after_action :session_update, only: %i(create update show destroy)
      after_action :drop_auth, only: %i(destroy)

      rescue_from Exception, with: :server_error
      rescue_from UnauthorizedError, with: :unauthorized
      rescue_from ActiveRecord::RecordNotFound, with: :unauthenticated
      rescue_from Tiun::Model::Account::InvalidPasswordError, with: :unauthenticated
      rescue_from ActionController::InvalidAuthenticityToken, with: :unauthenticated
      rescue_from NoTokenError, InvalidTokenError, with: :not_found
   end

   # POST /session.json
   def create
      @session = @current_user.generate_session

      respond_to do |format|
         format.html { redirect_to :root, notice: I18n.t("tiun.session.created") }
         format.json { render json: session_data }
      end
   end

   # PUT /session.json
   def update
      @session = @current_user.update_session(@token)

      respond_to do |format|
         format.html { redirect_to :root, notice: I18n.t("tiun.session.updated") }
         format.json { render json: session_data }
      end
   end

   # GET /session.json
   def show
      @session = @current_user.current_session(@token)

      respond_to do |format|
         format.html { redirect_to :root }
         format.json { render json: session_data }
      end
   end

   # DELETE /session.json
   def destroy
      @session = @current_user.destroy_session(@token)

      respond_to do |format|
         format.html { redirect_to :root, notice: I18n.t("tiun.session.deleted") }
         format.json { render json: serialize_collection([]) }
      end
   end

   protected

   def drop_auth
      session.delete("user")
   end

   def model_name
      @_model_name ||= 'Token'
   end

   def param_name
      @_param_name ||= model_name.tableize.singularize
   end

   def user_model
      @_user_model ||= User
   end

   def account_model_name
      @account_model_name ||= "Account"
   end

   def account_model
     @account_model ||= account_model_name.constantize
   end

   def locales
      I18n.available_locales
   end

   def supplement_names
      [:created_at, :updated_at]
   end

   def context
      @_context ||= {
         except: supplement_names,
         locales: locales,
         languages: @languages,
      }
   end

   def set_languages
      # NOTE the default values
      @languages ||= %i(ру)
   end

   def default_arg
      self.class.instance_variable_get(:@default_arg)&.[](action_name) || "id"
   rescue NameError
      "id"
   end

   def fetch_token
      if params[:type] && params[:token]
         raise NoTokenError unless token = params[:token]
         raise InvalidTokenError.new(auth) unless type = params[:type]
      else
         raise NoTokenError unless auth = request.headers["Authorization"]
         raise InvalidTokenError.new(auth) unless /(?<type>[\w]+) (?<token>.*)/ =~ auth
         raise InvalidTokenError.new(auth) unless require_token_table.include?(type)
      end

      attrs = { code: token, type: "Token::#{type[0..7].camelcase}", obsoleted_at: nil }
      @token = Token.where(attrs).first || raise(ActiveRecord::RecordNotFound)
   end

   def require_token_table
      {
        "update" => ["Validate", "Refresh"],
        "show" => ["Session"],
        "destroy" => ["Session", "Refresh"],
      }[action_name] || []
   end

   def parms
      @parms ||= params[account_model_name.downcase] || params
   end

   def account
      arg_name = default_arg

      @account ||=
         if !arg_name
            account_model.find(params[account_model.primary_key])
         elsif account_model.respond_to?("by_credentials_or_id")
            account_model.by_credentials_or_id(parms[arg_name]).first
         else
            account_model.where({ arg_name => parms[arg_name] }).first
         end# || raise(ActiveRecord::RecordNotFound)
   end

   def _permitted_filter
      @_permitted_filter ||= {}
   end

   def permitted_filter
      _permitted_filter[action_name] ||=
         if c = self.class.instance_variable_get(:@context)[action_name]
            (c.args || []).reject { |x| x.hidden }.map {|x| x.name }
         else
            [model.primary_key]
         end
   end

   def obsolete_token
      @token.update_attribute(:obsoleted_at, Time.zone.now)
   end

   def session_update
      if current_user
         session.update("user" => session_data)
      else
         session.delete('user')
      end
   end

   def current_user
      @current_user ||= super || account&.authenticated_user!(parms[:password])
   end

   def session_data
      #@current_user&.jsonize(only: %w(id last_login_at last_active_at accounts refresh_token session_token))
#            session_data = serialize_collection(user.update_session(session["user"]["refresh_token"]), auth_context)
#            session.update("user" => session["user"].merge(session_data))

      @session_data ||= current_user_data.merge(serialize_collection(@session))
   end
end

#::Auth::Controller = Tiun::Auth::Controller
