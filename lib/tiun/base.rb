require 'active_support'

module Tiun::Base
   class OutOfRangeError < StandardError; end
   class InvalidParamNameError < StandardError; end

   extend ActiveSupport::Concern

   included do
      include Tiun::Auth
      include Tiun::ErrorHandling

      before_action :set_context, if: ->{ respond_to?(:set_context) }, prepend: true
      before_action :fetch_objects, only: %i(index)
      before_action :new_object, only: %i(create)
      before_action :fetch_object, only: %i(show update destroy)
      before_action :assign_attributes, only: %i(update create)
      before_action :generate_answer, only: %i(destroy)
      before_action :parse_range, only: %i(index)
      after_action :return_range, only: %i(index)

      rescue_from ActiveRecord::RecordNotFound, InvalidParamNameError, with: :not_found
   end

   # GET /<objects>/
   def index
      respond_to do |format|
         format.html { render :index }
         format.json { render status: code, json: serialize_collection(paged_objects) }
         format.yaml { render status: code, yaml: serialize_collection(paged_objects).to_yaml }
         format.any { render status: code, json: serialize_collection(paged_objects), content_type: 'application/json' }
      end
   end

   # POST /<objects>.json
   def create
      object.save!

      respond_to do |format|
         format.html
         format.json { reloaded_object ? render(json: serialize(reloaded_object)) : head(:ok) }
         format.yaml { head :ok }
         format.any { render json: serialize(reloaded_object), content_type: 'application/json' }
      end
   end

   # PUT /<objects>/:id.json
   def update
      object.save!

      respond_to do |format|
         format.html
         format.json { render json: serialize(reloaded_object) }
         format.yaml { head :ok }
         format.any { render json: serialize(reloaded_object), content_type: 'application/json' }
      end
   end

   # GET /<objects>/:id.json
   def show
      respond_to do |format|
         format.html
         format.json { render json: serialize(object) }
         format.yaml { render yaml: serialize(object).to_yaml }
         format.any { render json: serialize(object), content_type: 'application/json' }
      end
   end

   # DELETE /<objects>/:id.json
   def destroy
      object.destroy

      respond_to do |format|
         format.html
         format.json { render json: @answer }
         format.yaml { head :ok }
         format.any { render json: @answer, content_type: 'application/json' }
      end
   end

   protected

   def code
      total == 0 ? :no_content : total > range.end + 1 ? :partial_content : :ok
   end

   def model_name
      @_model_name ||=
         Tiun.find_type(action_context.kind)&.model ||
         self.class.to_s.gsub(/.*::/, "").gsub("Controller", "").singularize
   end

   def model
      @_model ||= model_name.constantize
   rescue NameError
      User
   end

   def param_name
      @_param_name ||= model_name.tableize.singularize
   end

   def tiun_context
      self.class.instance_variable_get(:@context) || {}
   end

   def action_context
      [tiun_context[action_name]].flatten.find do |x|
         x && x["context_name"] == params["context_name"]
      end || {}.to_os
   end

   def tiun_args
      #[default_arg || model.primary_key])
      action_context.args || []
   end

   def _permitted_filter
      @_permitted_filter ||= {}
   end

   def permitted_filter
      _permitted_filter[action_name] ||=
         if action_context.blank?
            [model.primary_key]
         else
            (action_context.args || []).reject { |x| x.hidden }.map {|x| x.name }
         end
   end

   def _permitted_self
      @_permitted_self ||= {}
   end

   def permitted_self
      _permitted_self[action_name] ||=
         if action_context.blank?
            model.attribute_types.keys
         else
            (action_context.args || []).reject { |x| x.hidden }.map do |x|
               names = [x.name] | (x.alias ? x.alias.split(/\s*,\s*/) : [])

               case x.kind
               when /array/
                  names.reduce({}) {|r, n| r.merge(n => []) }
               when /json/
                  names.reduce({}) {|r, n| r.merge(n => {}) }
               else
                  names
               end
            end.flatten(1)
         end#.map do |x|
            # wheither attribute is array
            # model.type_for_attribute(x).respond_to?(:delimiter) ? { x => [] } : x
         #end
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

   def total
      @total ||=
         %i(total_size total_count count).reduce(nil) do |count, method|
            objects.respond_to?(method) && !count ? objects.send(method) : count
         end || raise
   end

   def paged_objects
      objects.range(range)
   end

   def current_context
      context_in = respond_to?(:context) ? context : {}

      context_in.merge(context_attributes)
   end

   def get_properties
      @get_properties ||=
         if k = action_context.kind
            Tiun.type_attributes_for(k, %i(read write))
         else
            model.attribute_types.keys
         end
   end

   def serialize_collection collection, context_in = {}
      collection.jsonize(current_context.merge(context_in).merge(only: get_properties))
   end

   def serialize object
      object.jsonize(current_context.merge(only: get_properties))
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
      if perm = action_context.policy
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

   def reload_scope
      with_others(object_scope.base_class.where(object.primary_key => object[object.primary_key]))
   end

   def reloaded_object
      reload_scope.first
   end

   def new_object
      @object = model.new
   end

   def generate_answer
      @answer = serialize(object)
   end

   def current_attrs
      case action_name
      when 'update', 'create'
         params.require(param_name).permit(*permitted_self, **permitted_children).to_h
      else
         {}
      end
   end

   def context_attributes attrs = current_attrs
      action_context.contexted_attributes.map {|_, names| names.reduce(nil) {|r, name| r || attrs[name] }}.to_h
   end

   def assign_attributes
      default_attributes =
        respond_to?(:default_attributes) ? self.default_attributes.merge(context_attributes).map do |(key, value)|
            [key.to_s, value]
         end.to_h : {}

      assign_attributes_for(object, default_attributes.merge(current_attrs))
   end

   def assign_attributes_for object, attrs
      attrs.reduce(object) do |o, (key, value)|
         if o.respond_to?("#{key}=")
            o.send("#{key}=", value)
         else # just set variable for the object
            o.instance_variable_set(:"@#{key}", value)
         end

         o
      end
   end

   def fetch_object
      object
   end

   def object
      @object ||= with_others(object_scope).first || raise(ActiveRecord::RecordNotFound)
   end

   def fetch_objects
      objects
   end

   def object_scope
      apply_scope(model.all, [default_arg || model.primary_key])
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
      apply_scope(model.default_scoped, tiun_args.map { |a| a.name })
   end

   def is_arg_requires_skip? arg_in
      skip = tiun_args.find {|x| x.name == arg_in }&.skip

      return true if skip.to_s =~ /args/
   end

   def apply_scope rela = self.model.default_scoped, args = []
      args.reduce(rela) do |rel, arg_in|
         arg_prop = tiun_args.find { |x| arg_in == x.name }
         names = [arg_prop&.source || arg_in, arg_prop&.alias&.split(',')].flatten.compact
         param_names = params.keys & names

         next rel unless param_names.any? && !is_arg_requires_skip?(arg_in)

         arg = param_names.first || arg_in

         apply_by_names(names, apply_sec_names(names, rel, arg), arg)
      end
   end

   # apply secunda /// http://lingvo.asu.ru/latin/morfo/y45.html
   def apply_sec_names names, rel, arg
      names.reduce(rel) do |rel, attr_name|
         if model.respond_to?("sec_#{attr_name}")
            begin
               rel.send("sec_#{attr_name}", params[arg], current_context)
            rescue ArgumentError
               rel.send("sec_#{attr_name}", params[arg])
            end
         else
            rel
         end
      end
   end

   def apply_by_names names, rel, arg
      names.reduce(rel) do |rel, attr_name|
         if model.respond_to?("by_#{attr_name}")
            begin
               rel.send("by_#{attr_name}", params[arg], current_context)
            rescue ArgumentError
               rel.send("by_#{attr_name}", params[arg])
            end
         elsif model.respond_to?("#{attr_name}") && params[arg] =~ /^true|t$/
            rel.send(attr_name)
         elsif model.attribute_names.include?(attr_name)
            # TODO protect params[arg] is non string or integer
            rel.where({ attr_name => params[arg] })
         else
            # Kernel.puts "WARN: Invalid scope by property '#{attr_name}'"
            rel
         end
      end
   end

   # +with_others+ collects relation with "with_" methods defiend in the scheme
   # args:
   # * rela - relation not a pure model exactly
   # * args - arguments defaulted to the tiun scope arguments
   #
   def with_others rela, args = self.scope_args
      k = action_context.kind

      Tiun.sublings_for(k, :write).reduce(rela) do |r, (sub, props)|
         if r.respond_to?("with_#{sub}")
            attrs = props ? {only: props} : {}

            begin
               r.send("with_#{sub}", current_context.merge(attrs).merge(args))
            rescue ArgumentError
               r.send("with_#{sub}")
            end
         else
            warn "WARN: Invalid scope by property '#{sub}'"
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
