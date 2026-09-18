require 'rails'
require 'active_record'

require 'tiun/model'

class Tiun::Engine < ::Rails::Engine
   isolate_namespace Tiun

   engine_name 'tiun'

   paths["app"] << "#{config.root}/lib"
   paths["app/controllers"] << "#{config.root}/lib"
   paths["app/views"] << "#{config.root}/lib"
   paths["config/routes.rb"]  << "#{config.root}/lib/config/routes.rb"

   config.i18n.load_path += Dir[Tiun::Engine.root.join('lib', 'config', 'locale', '**', '*.{yaml,yml}')]

   config.autoload_paths += Dir["#{config.root}/lib"]
   config.autoload_paths += Dir["#{config.root}/lib/config"]

   config.to_prepare do
      ActiveSupport.on_load(:active_record) do
         Tiun.setup
         extend Tiun::Model
      end
   end
end
