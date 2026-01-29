class Tiun::MetaController < ActionController::Base
   # GET /meta/
   def index
      joint = Tiun.config.values.reduce({}) {|res, h| res.merge(h) }

      render json: joint.as_json
   end
end

MetaController = Tiun::MetaController
