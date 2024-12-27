require 'active_support'
require 'tiun/auth'

module Tiun::Auth::Controller
   class NoTokenError < StandardError; end
   class InvalidTokenError < StandardError; end
   class UnauthorizedError < StandardError; end

   extend ActiveSupport::Concern

   included do
      include Tiun::Auth

      before_action :set_languages
      before_action :authenticate
      before_action :fetch_token, only: %i(update show destroy)
      before_action :authorize!, only: %i(create update show destroy)
      after_action :obsolete_token, only: %i(update show destroy)
      after_action :session_update, only: %i(create update show destroy)
      after_action :drop_auth, only: %i(destroy)

      rescue_from Exception, with: :exception
      rescue_from UnauthorizedError, with: :unauthorized
      rescue_from ActiveRecord::RecordNotFound, with: :unauthenticated
      rescue_from Tiun::Model::Account::InvalidPasswordError, with: :unauthenticated
      rescue_from NoTokenError, InvalidTokenError, with: :invalid_token
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

   def unauthenticated e
      render_code 401
   end

   def unauthorized e
      render_code 403
   end

   def render_code code
      args = params.permit(*permitted_filter).to_h
      res = { status: code, json: { args: args }}

      args.present? ? render(**res) : head(code)
   end

   def invalid_token e
      render_code 404
   end

   def exception e
      error = "[#{e.class}]{exception}> #{e.message} \n\t #{e.backtrace.join("\n\t")}"
      args = params.permit(*permitted_filter).to_h
      render json: { args: args, error: error }, status: 500
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

   def authenticate
      @current_user ||=
         if session["user"]
            User.find_by_id(session["user"]["id"])
         else
            account&.authenticated_user!(parms[:password])
         end
   end

   def authorize!
      @current_user ||=
         if @token
            @token.tokenable.is_a?(user_model) ? @token.tokenable : @token.tokenable.user
         end || raise(UnauthorizedError)
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
      session.update("user" => session_data)
   rescue ActiveRecord::RecordNotFound
      session.update("user" => nil)
   end

   def current_user
      @current_user ||= authenticate
   end

   def session_data
      #@current_user&.jsonize(only: %w(id last_login_at last_active_at accounts refresh_token session_token))

      @session_data ||= current_user_data.merge(serialize_collection(@session))
   end
end

Auth::Controller = Tiun::Auth::Controller
