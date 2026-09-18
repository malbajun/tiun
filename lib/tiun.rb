begin
   require 'pry'
rescue NameError, LoadError
end
require 'erb'
require 'action_controller'
require 'active_record'

require "tiun/mixins"
require "tiun/version"
require "tiun/migration"
require "tiun/attributes"
require "tiun/error_handling"
require "tiun/base"
require "tiun/auth"
require "tiun/core_helper"

module Tiun
   class NoRailsError < StandardError ;end
   class InvalidControllerError < StandardError ;end
   class InvalidModelError < StandardError ;end
   extend Tiun::Migration
   extend Tiun::Attributes

   MAP = {
      'get' => {
         %r{(?:/(?<c>[^/]+)/:[^/]+).json} => 'show',
         %r{(?:/(?<c>[^/]+)/@(?<cc>[^/]+)).json} => ':cc',
         %r{(?:/(?<c>[^:/]+)).json} => 'index',
      },
      'post' => 'create',
      'patch' => 'update',
      'put' => 'update',
      'delete' => 'destroy'
   }

   TYPE_MAP = {
      "string" => "string",
      "sequence" => "integer",
      "uri" => "string",
      "list" => nil,
      "json" => "jsonb",
      "enum" => "string",
   }

   TEMPLATES = {
      model: ERB.new(IO.read(File.join(File.dirname(__FILE__), "tiun", "automodel.rb.erb"))),
      policy: ERB.new(IO.read(File.join(File.dirname(__FILE__), "tiun", "autopolicy.rb.erb"))),
      controller: ERB.new(IO.read(File.join(File.dirname(__FILE__), "tiun", "autocontroller.rb.erb"))),
   }

   class << self
      def setup
         unless @config
            files = Dir.glob(::Rails.root&.join("config", "tiun", "*.{yml,yaml}")) |
                    Dir.glob(::Rails.root&.join("config", "tiun.{yml,yaml}"))

            setup_with(*files)

            true
         else
            false
         end if defined?(::Rails) && ::Rails.root
      end

      def setup_if_not
         @setup ||= setup
      end

      def setup_with *files
         # setup_migrations

         files.each do |file|
            config = append_config(file)
            # load_error_codes_from( config )
            load_types_from(config)
            load_defaults_from(config)
            %i(model controller policy).each do |kind|
               instance_variable_set("@#{kind.to_s.pluralize}", parse_objects(kind, config))
            end
            load_routes_from(config)
         end

         # validates
         config
      end

      def kind_for context
         context.methods.reduce(nil) { |k, m| k || m.kind }
      end

      def model_name_for context
         if type = find_type(kind_for(context))
            type.model || type.name
         else
            context.model ||
               %r{(?:/(?<c>[^/]+)/:[^/]+|/(?<c>[^:/]+)).json} =~ context.path && c ||
               context.name.split(".").first
         end
      end

      def object_name_for context
         if type = find_type(kind_for(context))
            type.controller || type.model || type.name
         else
            context.controller ||
               %r{^(?:(?<c>.+)/:[^/]+|/(?<c>[^:]+)).json} =~ context.path && c ||
               context.name.split(".").first
         end
      end

      # => "api/v1/session" inferred from path
      def controller_name_base_for context
         context.controller ||
            if %r{^(?:/(?<c>.+)/:[^/]+|/(?:(?<cc>[^:]+)/(?<ccc>create)|(?<cccc>[^:]+)(?:(?<ccccc>.*))?)).json} =~ context.path
               (c || cc || cccc).chomp('/')
            elsif type = find_type(kind_for(context))
               type.controller || type.model || type.name
            end ||
               context.name.split(".").first ||
                  error(:no_controller_name_defined, { name: context.name }, InvalidControllerError)
      end

      # => "api/v1/session" => api_v1_session inferred from path
      def as_prefix_base_for context
         context.as ||
            if %r{^(?:/(?<c>.+)/:[^/]+|/(?:(?<cc>[^:]+)/(?<ccc>create)|(?<cccc>[^:]+))).json} =~ context.path
               if c
                  c.singularize
               elsif cc
                  "#{ccc}_#{cc.singularize}"
               else
                  cccc.pluralize
               end
            elsif type = find_type(kind_for(context))
               type.controller || type.model || type.name
            end ||
               context.name.split(".").first ||
                  error(:no_controller_name_defined, { name: context.name }, InvalidControllerError)
      end

      def model_title_for context
         name = model_name_for(context)

         name ? name.singularize.camelize : raise(InvalidModelError)
      end

      def controller_title_for context
         controller_name_base_for(context).pluralize.camelize + 'Controller'
      end

      def controller_default_arg_for context
         context.key || /:(?<arg>[^\.]+)/.match(context.path)&.[](:arg)
      end

      def route_controller_title_for context
         controller_name_base_for(context).pluralize.tableize
      end

      def route_as_prefix_for context
         as_prefix_base_for(context).parameterize.underscore
      end

      def table_title_for context
         context.table || model_name_for(context).tableize
      end

      def table_title_for type
         type.name.tableize
      end

      def policy_title_for context
         context.policy || model_name_for(context).singularize.camelize + "Policy"
      end

      # find type record in type record table for last version of
      #
      def find_type type_names_in
         type_names = "#{type_names_in}".split(/\s+/)

         types.reduce(nil) do |t, type|
            type_names.include?(type.name) && (!t || !t.version || type.version && t.version < type.version) ? type : t
         end unless type_names.blank?
      end

      # generates a hash to collect all subling relation for the specificed kind type
      #
      def sublings_for type_name_in, kind_in = %i(read write)
        kind = [kind_in].flatten
        withes_in = withes(type_of(type_name_in)).map {|x| [x, x]}.to_h

        sublings["#{type_name_in}:#{kind.join(',')}"] ||=
           type_attributes_for(type_name_in, kind).reduce(withes_in) do |res, value_in|
              if value_in.is_a?(Hash)
                 res.merge(value_in)
              else
                 res
              end
           end
      end

      def contexted_attributes_for tiun_args
         (tiun_args || []).reduce({}) do |attrs, arg|
            key =
               case arg.context
               when true
                  arg.name
               when String
                  arg.context
               end

            key ? attrs.merge(key => [arg.name] | (arg.alias&.split(/\s*,\s*/)|[])) : attrs
         end
      end

      def fill_in_context context_in
         context = YAML.load(context_in, permitted_classes: [OpenStruct, Symbol])

         context.map do |(action_name, actx)|
            new =
               actx.merge({
                  contexted_attributes: contexted_attributes_for(actx.args)
               })

            [action_name, new]
         end.to_h
      end

      def withes type
         return {} unless type

         withes = type.with.is_a?(Array) ? type.with : type.with.to_s.split(/\s*,\s*/)

         withes.map {|x| x.is_a?(OpenStruct) ? x.to_h.values : x }.flatten
      end

      def type_of type_name_in
         return type_name_in.is_a?(OpenStruct) ? type_name_in : find_type(type_name_in)
      end

      # +type_attributes_for+ renders attributes array for the type name or type itself specified,
      # if no type name has been found, it returns a blank array.
      #
      def type_attributes_for type_name_in, kind = %i(read write)
         type = type_of(type_name_in)

         return [] unless type

         names = type.fields.map {|x| x.name }

         withes(type).reduce(type.fields || []) do |res, x|
            if i = res.index {|y| y.name == x }
               res[0...i] | [res[i].merge({rela: true}) ] | res[i + 1..-1]
            elsif names.include?(x)
               res | [{name: x, rela: true}.to_os]
            else
               res
            end
         end.map do |x|
            next nil unless x.to_h.keys.select do |y|
                  /only$/ =~ y
               end.reduce(kind) do |k, prop|
                  x[prop] ? ["#{prop}".sub("only","").to_sym] & k : k
               end.any?

            if sub = Tiun.find_type(x.kind)
               { x.name => type_attributes_for(sub, kind) }
            elsif x.source
               { x.name => x.source.to_s }
            elsif x.rela
               { x.name => x.name }
            else
               x.name
            end
         end.compact
      end

      def detect_type type_in
         type = TYPE_MAP[type_in]
         type || !type.nil? && "reference" || nil
      end

      def load_types_from config
         @types = types | (config.types || [])
      end

      def action_names_for context
         actions = (context["methods"] || {}).map do |method|
            method_name = method.name
            rule = MAP[method_name]

            action =
               method.action || (rule.is_a?(String) && rule || rule.reduce(nil) do |a, (re, action)|
                  a ||
                     if m = re.match(context.path)
                        /^:(?<var>.*)/ =~ action ? m[var] : action
                     end
               end)

            # TODO validated types
            if ! action
               error :no_action_detected_for_resource_method, { name: context.name, method: method_name }
            end

            action ? [action, method.merge(context_name: context.name)] : nil
         end.compact.to_h

         if actions.blank?
            error :no_valid_method_defined_for_resource, { name: context.name }
         end

         actions
      end

      def string_eval string, name
         tokens = name.split("::")[0...-1]

         tokens.reduce(Object) do |o, token|
            o.constants.include?(token.to_sym) && o.const_get(token) || o.const_set(token, Module.new)
         end

         eval(string)
      end

      def value_eval_deep value
         case value
         when String
            if /@(?<ev>[^@]+)@/ =~ value
               value_tmp = ev.split('.').reduce(Object) do |res, token|
                  if /^[A-Z]/ =~ token
                     token.constantize
                  elsif res.respond_to?(token)
                     res.send(token)
                  else
                     raise("Can't apply '#{token}' to object #{res}")
                  end
               end

               value_tmp.is_a?(Proc) ? value_tmp[] : value_tmp
            else
               value
            end
         when OpenStruct
            value.reduce(OpenStruct.new) {|res, x, y| res.merge({x => value_eval_deep(y)}.to_os) }
         when Hash
            value.reduce({}) {|res, (x, y)| res.merge(x => value_eval_deep(y)) }
         when Array
            value.map {|x| value_eval_deep(x) }
         else
            value
         end
      end

      def config_reduce config, default
         config.resources.reduce(default) do |res, context|
            if context.name.is_a?(String)
               yield(res, context.name, context)
            else
               res
            end
         end
      rescue NoMethodError
         error :no_resources_section_defined_in_config, {config: config, default: default}

         default
      end

      def load_defaults_from config
         @defaults = defaults.deep_merge(config.defaults) if config.defaults
      end

      def parse_objects kind, config
         config_reduce(config, send(kind.to_s.pluralize)) do |res, name, context|
            object_name = send("#{kind}_title_for", context)

            unless search_for(kind.to_s.pluralize, object_name)
               object_in = constantize(object_name)
               code = TEMPLATES[kind].result(binding)
               object = string_eval(code, object_name)

               res | [{ name: object_name, code: code, const: object }.to_os]
            else
               res
            end
         end
      end

      def flex_merge src, tgt
         src.reduce(tgt.dup) do |res, (key, value)|
            res[key] =
               if res[key]
                  (res[key].is_a?(Array) ? res[key] : [res[key]]) | [value]
               else
                  res[key] = value
               end

            res
         end
      end

      def load_routes_from config
         @routes =
            config_reduce(config, routes) do |r, name, context|
               controller = route_controller_title_for(context)
               as_prefix = route_as_prefix_for(context)
               actions = action_names_for(context)

               actions.reduce(r) do |res, (action, method)|
                  /(\.(?<format>[^.]+))$/ =~ context.path

                  path =
                     /(?<pre>.*)<(?<key>\w+)>(?<post>.*)/ =~ context.path &&
                     "#{pre}:#{key}#{post}" || context.path

                  if res.select {|x| x[:uri] == path && x[:kind] == action }.blank?
                     attrs = { uri: path, path: "#{controller}##{action}", kind: method.name, as: as_prefix }
                     attrs = attrs.merge(options: {defaults: { context_name: name }})
                     attrs = attrs.deep_merge(options: {defaults: { format: format }, constraints: { format: format }}) if format

                     res | [attrs]
                  else
                     res
                  end
               end
            end
      end

      def default_route
         {
            uri: '/meta.json',
            path: 'meta#index',
            kind: 'get',
            options: { defaults: { format: 'json' }, constraints: { format: 'json' }}
         }
      end

      def draw_routes e
         setup_if_not
         routes.each do |route|
            attrs = { route[:uri] => route[:path] }.merge(route[:options])
            e.send(route[:kind], **attrs)
         end
      end

      def search_for kind, value
         send(kind).find {|x| x.name == value }
      end

      def search_all_for kind, value
         send(kind).select {|x| x.name == value }
      end

      def error_codes
         @error_codes ||= []
      end

      def types
         @types ||= []
      end

      def sublings
         @sublings ||= {}
      end

      def models
         @models ||= []
      end

      def policies
         @policies ||= []
      end

      def controllers
         @controllers ||= []
      end

      def routes
         @routes ||= [default_route]
      end

      def config
         @config ||= {}
      end

      def defaults
         @defaults ||= {}.to_os
      end

      def errors
         @errors ||= []
      end

      def append_config file
         config_in = YAML.load(IO.read( file )).to_os
         config[ File.expand_path( file )] =
            config_in.reduce(OpenStruct.new) do |res, k, v|
               res[k] = value_eval_deep(v)

               res
            end

      end

      def settings
         @settings ||= setup_classes(tiuns.map { | model | [ model.name.underscore.to_sym, model.tiun ]}.to_h)
      end

      def tiuns
         ::Rails.configuration.paths['app/models'].to_a.each do | path |
            Dir.glob("#{path}/**/*.rb").each { |file| require(file) }
         end

         ActiveRecord::Base.tiuns
      end

      def constantize name
         name.constantize
      rescue NameError
      end

      def base_models
         @base_models ||= {}
      end

      def table_exist? name
         ActiveRecord::Base.connection.data_source_exists?(name.to_s.tableize)
      end

      def base_model name = nil
        #binding.pry
         base_models[name] ||= table_exist?(name) ?
            (defined?(ApplicationRecord) ?  ApplicationRecord : ActiveRecord::Base) : ActiveModel::Model

         #ActiveRecord::Base.ancestors.select {|x| x.class.to_s == "Module" && x.name =~ /ActiveRecord::/ }.each {|x| User.include(x) }
      end

      def base_controller
         @base_controller ||= defined?(ApplicationController) ? ApplicationController : ActionController::Base
      end

      def template_controller_for context
         t = context.template&.camelize

         self.const_get(t).const_get(:Controller)
      rescue NameError, TypeError
         ::Tiun::Base
      end

      def error code, options, exception = nil
         errors << { code: code, options: options }

         exception ? raise(exception) : errors.last
      end

      def valid?
         errors.blank?
      end

      def root
         Gem::Specification.find_by_name( "tiun" ).full_gem_path
      end

   end
end

require "tiun/policy"
require "tiun/engine"
