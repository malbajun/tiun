require 'rails'
require 'active_record'

require 'tiun/model'

class Tiun::Engine < ::Rails::Engine
   isolate_namespace Tiun

   engine_name 'tiun'

   paths["app"] << "lib"
   paths["app/controllers"] << "lib"
   paths["app/views"] << "lib"
   paths["config/routes.rb"]  << "lib/config/routes.rb"

   config.i18n.load_path += Dir[Tiun::Engine.root.join('lib', 'config', 'locale', '**', '*.{yaml,yml}')]

   config.to_prepare do
      ::ActiveRecord::Base.extend(Tiun::Model)
      Tiun.setup
   end
end

Engine = Tiun::Engine
