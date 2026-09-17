class Tiun::MetaController < ActionController::Base
      # GET /meta/
      def index
         joint = Tiun.config.values.reduce({}.to_os) {|res, h| res.deep_merge(h) }

         render json: joint.to_h.as_json
      end
end

MetaController = Tiun::MetaController
