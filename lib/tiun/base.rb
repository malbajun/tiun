require 'active_support'

module Tiun::Base
   class OutOfRangeError < StandardError; end
   class InvalidParamNameError < StandardError; end

   extend ActiveSupport::Concern

   included do
      include Tiun::Auth

      attr_reader :object

      #attr_accessor :params
      #define_callbacks :subscribe
      # include Kaminari::ConfigurationMethods
      #class_attribute :_helpers
      #self._helpers = Module.new
      #include ActiveSupport::Configurable
      #config_accessor :co
#      helper_method :cookies if defined?(helper_method)
#      around_perform do |job, block, _|
#         I18n.with_locale(I18n.locale.to_s, &block)
#      include Pundit

      before_action :set_languages, if: ->{ respond_to?(:set_languages) }
 #     before_action :authenticate_user
#      before_action :set_tokens, only: %i(index)
#      before_action :set_page, only: %i(index)
#      before_action :set_locales
      before_action :new_object, only: %i(create)
      before_action :fetch_object, only: %i(show update destroy)
      before_action :fetch_objects, only: %i(index)
      before_action :fetch_ac_objects, only: %i(ac)
      before_action :parse_range, only: %i(index ac)
      after_action :return_range, only: %i(index ac)
      # before_action :authorize!

      rescue_from Exception, with: :server_error
      rescue_from ActionView::MissingTemplate, with: :missing_template
      rescue_from ActionController::ParameterMissing, with: :unprocessable_entity
      rescue_from ActiveRecord::RecordNotUnique,
                  ActiveRecord::RecordInvalid,
                  ActiveRecord::RecordNotSaved,
                  CarrierWave::IntegrityError, with: :unprocessable_entity
      rescue_from ActiveRecord::RecordNotFound, InvalidParamNameError, with: :not_found
      rescue_from OutOfRangeError, with: :out_of_range
      rescue_from Tiun::Model::Auth::InvalidTokenError, with: :unauthenticated
      rescue_from Tiun::Policy::NotAuthorizedError, with: :unauthorized

#      has_scope :with_token, only: %i(index all)
#      has_scope :with_tokens, only: %i(index), type: :array

   end

   # GET /<objects>/
   def index
      respond_to do |format|
         format.html { render :index }
         format.json { render status: code, json: serialize_collection(paged_objects) }
         format.jsonp { render status: code, json: serialize_collection(paged_objects) }
         format.any { render status: code, json: serialize_collection(paged_objects), content_type: 'application/json' }
      end
   end

   # POST /<objects>.json
   def create
      object.save!

      respond_to do |format|
         format.html
         format.json { render json: serialize(reloaded_object) }
         format.jsonp { head :ok }
         format.any { render json: serialize(reloaded_object), content_type: 'application/json' }
      end
   end

   # PUT /<objects>/:id.json
   def update
      object.update!(permitted_params)

      respond_to do |format|
         format.html
         format.json { render json: serialize(reloaded_object) }
         format.jsonp { head :ok }
         format.any { render json: serialize(reloaded_object), content_type: 'application/json' }
      end
   end

   # GET /<objects>/:id.json
   def show
      respond_to do |format|
         format.html
         format.json { render json: serialize(object) }
         format.jsonp { render json: serialize(object) }
         format.any { render json: serialize(object), content_type: 'application/json' }
      end
   end

   # DELETE /<objects>/:id.json
   def destroy
      answer = serialize(object)
      object.destroy

      respond_to do |format|
         format.html
         format.json { render json: answer }
         format.jsonp { head :ok }
         format.any { render json: answer, content_type: 'application/json' }
      end
   end

   # GET /<objects>/ac.json
   def ac
      respond_to do |format|
         format.json {
            render json: {
               list: objects.limit(ac_limit).jsonize(ac_context),
               total: objects.total_count
            }
         }
      end
   end

#   def dashboard
#      settings = { settings: Tiun.settings, locales: @locales }
#
#      render inline: react_component('Dashboard', settings), layout: 'tiun'
#   end
#
   protected

   def code
      total == 0 ? :no_content : total > range.end + 1 ? :partial_content : :ok
   end

   def model_name
      @_model_name ||= Tiun.find_type(tiun_context[action_name]&.kind)&.model || super
   end

   def param_name
      @_param_name ||= model_name.tableize.singularize
   end

#   def serializer
#      @serializer ||= "#{model_name}Serializer".constantize
#   end
#
#   def list_serializer
#      @list_serializer ||= "#{model_name}ListSerializer".constantize
#   end
#
#   def objects_serializer
#      list_serializer.new(model: model)
#   end
#
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

   def ac_limit
      500
   end

   def ac_context
      @_ac_context ||= { only: %i(key value) }
   end

   def tiun_context
      self.class.instance_variable_get(:@context) || {}
   end

   def tiun_args
      tiun_context[action_name]&.args || []
   end

   def _permitted_filter
      @_permitted_filter ||= {}
   end

   def permitted_filter
      _permitted_filter[action_name] ||=
         if c = tiun_context[action_name]
            (c.args || []).reject { |x| x.hidden }.map {|x| x.name }
         else
            [model.primary_key]
         end
   end

   def _permitted_self
      @_permitted_self ||= {}
   end

   def permitted_self
      _permitted_self[action_name] ||=
         if c = tiun_context[action_name]
            (c.args || []).reject { |x| x.hidden }.map {|x| x.kind == 'json' ? {x.name => {}} : x.name }
         else
            model.attribute_types.keys
         end
   end

   def permitted_children
      @_permitted_children ||=
         model.nested_attributes_options.reduce({}) do |res, (name, opts)|
            child_model = model.reflections[name.to_s].klass
            value = child_model.attribute_types.keys
            value << :_destroy if opts[:allow_destroy]
            res["#{name}_attributes"] = value - supplement_names.map(&:to_s)

            res
         end
   end

   def permitted_params
      params.require(param_name).permit(*permitted_self, **permitted_children)
   end

   def total
      @total ||=
         %i(total_size total_count count).reduce(nil) do |count, method|
            objects.respond_to?(method) && !count ? objects.send(method) : count
         end || raise
   end

   def paged_objects
      objects.range(range)
   end

   def get_properties
      @get_properties ||=
         if k = tiun_context[action_name]&.kind
            Tiun.type_attributes_for(k, %i(read write))
         else
            model.attribute_types.keys
         end
   end

   def serialize_collection collection, context_in = {}
      collection.jsonize(context.merge(context_in).merge(only: get_properties))
#         format.json { render :index, json: objects, locales: locales,
#                                      serializer: objects_serializer,
#                                      each_serializer: serializer,
#                                      total: objects.total_count,
#                                      page: page,
#                                      per: per }
   end

   def serialize object
      object.jsonize(context.merge(only: get_properties))
#         format.json { render :show, json: @object, locales: @locales,
#                                     serializer: serializer }
   end

   def per
      @per ||= (params[:per] ||
         tiun_args.reduce(nil) { |res, x| res || x.name == "per" && x.default || nil } || 25).to_i
   end

   def page
      @page ||= (params[:page] || params[:p] || 1).to_i
   end

   def set_tokens
      @tokens ||= params[:with_tokens] || []
   end

   def default_arg
      self.class.instance_variable_get(:@default_arg)[action_name]
   rescue NameError
      "id"
   end

   def range
      @range
   end

   def allowing_permission
      if perm = tiun_context[action_name].policy
         [perm].flatten.map { |x| x.split(",") }.flatten
      end
   end

   def objects
      @objects ||= with_others(objects_scope)
   end

   # callbacks
   def parse_range
      @range =
         if /(?<b>[0-9]+)-(?<e>[0-9]+)/ =~ request.headers["Range"]
            (b.to_i..e.to_i - 1)
         else
            ((page - 1) * per..(page - 1) * per + per - 1)
         end

      raise OutOfRangeError if total > 0 && @range.begin >= total || @range.end < @range.begin
   end

   def reloaded_object
      with_others(object_scope.base_class.where(object.primary_key => object[object.primary_key])).first
   end

   def new_object
      @object = model.new(permitted_params)
   end

   def fetch_object
      @object = with_others(object_scope).first || raise(ActiveRecord::RecordNotFound)
   end

   def object
      @object ||= fetch_object
   end

   def fetch_objects
      objects
   end

   def fetch_ac_objects
      @objects = apply_scopes(model)
   end

   def object_scope
      apply_scope(model, [default_arg || model.primary_key])
   end

   def scope_args
      tiun_args.reduce({}) do |res,x|
         if value = params[x.name] || params[x.alias]
            res[x.name.to_sym] = value
         end

         res
      end
   end

   def objects_scope
      apply_scope(model, tiun_args.map { |a| a.name })
   end

   def is_arg_requires_skip? arg_in
      skip = tiun_args.find {|x| x.name == arg_in }&.skip

      return true if skip.to_s =~ /scope/
   end

   def apply_scope model = self.model, args = []
      args.reduce(model) do |rel, arg_in|
         arg_prop = tiun_args.find { |x| arg_in == x.name }
         names = [arg_prop&.source || arg_in, arg_prop&.alias&.split(',')].flatten.compact
         param_names = params.keys & names

         next rel unless param_names.any? && !is_arg_requires_skip?(arg_in)

         arg = param_names.first || arg_in
         names.reduce(rel) do |rel, attr_name|
            if model.respond_to?("by_#{attr_name}")
               begin
                  rel.send("by_#{attr_name}", params[arg], context)
               rescue ArgumentError
                  rel.send("by_#{attr_name}", params[arg])
               end
            elsif model.respond_to?("#{attr_name}") && params[arg] =~ /^true|t$/
               rel.send(attr_name)
            elsif model.attribute_names.include?(attr_name)
               rel.where({ attr_name => params[arg] })
            else
               # Kernel.puts "WARN: Invalid scope by property '#{attr_name}'"
               rel
            end
         end
      end
   end

   def with_others rela, args = self.scope_args
      k = tiun_context[action_name]&.kind

      Tiun.sublings_for(k, :write).reduce(rela) do |r, (sub, props)|
         if r.respond_to?("with_#{sub}")
            attrs = props ? {only: props} : {}

            begin
               r.send("with_#{sub}", context.merge(attrs).merge(args))
            rescue ArgumentError
               r.send("with_#{sub}")
            end
         else
            # Kernel.puts "WARN: Invalid scope by property '#{attr_name}'"
            r
         end
      end
   end

   def return_range
      response.headers["Access-Control-Expose-Headers"] = "Content-Range"
      response.headers["Accept-Ranges"] = "records"
      response.headers["Content-Range"] = "records #{range.begin}-#{range.end}/#{total}"
      # NOTE: HTTP isn't supported range except bytes https://stackoverflow.com/a/9480391/446267
      # response.headers["Content-Length"] = [range.end + 1, total].min - range.begin
   end
end

Base = Tiun::Base
