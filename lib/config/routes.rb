module Routes
   Mime::Type.register "application/yaml", :yaml

   Tiun::Engine.routes.draw do
      Tiun.draw_routes(self)
   end
end
