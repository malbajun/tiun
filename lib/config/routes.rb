module Routes
   Mime::Type.register "application/jsonp", :jsonp

   Tiun::Engine.routes.draw do
      Tiun.draw_routes(self)
   end
end
