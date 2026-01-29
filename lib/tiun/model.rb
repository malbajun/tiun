require 'tiun/version'

module Tiun::Model
   # +tiun+ sets up tiuner for the model. This exports corresponding record fields to default
   # dashboard method, which loads the react component. When the model has been set up, the method
   # returns the compiled data of the model.
   #
   # currently doing nothing
   #
   # Examples:
   #
   #     tiun
   #
   #     Model.tiun
   #
   def tiun
   end

   # +tiuns+ returns lists of the tiuned models. In case the list is absent returns blank
   # +Array+.
   #
   # Examples:
   #
   #     Model.tiuns # => [ Model ]
   #
   #     ActiveRecord::Base.tiuns # => []
   #
   def tiuns
      self.class.instance_variable_get(:@tiuns) || []
   end

   # Specify range to return
   def range range
      if range.is_a?(Range)
         offset(range.begin).limit(range.end - range.begin + 1)
      else
         unscope(:limit).unscope(:offset)
      end
   end

   protected

    # :nodoc:
   def _tiun_parse_model
      self.attribute_types.map do |( name, attr )|
         if !["created_at", "updated_at"].include?( name )
            kind = case attr.class.to_s.split("::").last
            when /Integer|SQLite3Integer/
               :integer
            when "String"
               :string
            when "Text"
               :text
            when /DateTime|TimeZoneConverter/
               :datetime
            when "Date"
               :date
            when "Time"
               :time
            when "Boolean"
               :boolean
            else
            end

            if kind
               props = { type: kind }
               props[ :size ] = attr.limit if attr.limit

               [name.to_sym, props]
            end
         end
      end.compact.to_h
   rescue ActiveRecord::ConnectionNotEstablished
      []
   end
end

Model = Tiun::Model
