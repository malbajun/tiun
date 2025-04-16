require 'tiun/version'

module Tiun::Model
   # +tiun+ sets up tiuner for the model. This exports corresponding record fields to default
   # dashboard method, which loads the react component. When the model has been set up, the method
   # returns the compiled data of the model.
   #
   # Examples:
   #
   #     tiun
   #
   #     Model.tiun
   #
   def tiun
      ## return self.instance_variable_get(:@tiun) if self.instance_variables.include?(:@tiun)

      ## self.instance_variable_set(:@tiun, { fields: _tiun_parse_model})

      ## tiuns = self.class.instance_variables.include?(:@tiun) && self.class.instance_variable_get(:@tiuns) || []
      ## tiuns << self
      ## self.class.instance_variable_set(:@tiuns, tiuns)
      #
      # belongs_to, has_many, has_one
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

# {"id"=>#<ActiveModel::Type::Integer:0x00007fbd4365de18 @limit=4, @precision=nil, @range=-2147483648...2147483648, @scale=nil>,
# "date"=>#<ActiveModel::Type::String:0x00007fbd4363bb38 @false="f", @limit=nil, @precision=nil, @scale=nil, @true="t">,
# "language_code"=>#<ActiveModel::Type::String:0x00007fbd4363bb38 @false="f", @limit=nil, @precision=nil, @scale=nil, @true="t">,
# "alphabeth_code"=>#<ActiveModel::Type::String:0x00007fbd4363bb38 @false="f", @limit=nil, @precision=nil, @scale=nil, @true="t">,
# "created_at"=>#<ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Timestamp:0x00007fbd4363f0f8 @limit=nil, @precision=nil, @scale=nil>,
# "updated_at"=>#<ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Timestamp:0x00007fbd4363f0f8 @limit=nil, @precision=nil, @scale=nil>,
# "place_id"=>#<ActiveModel::Type::Integer:0x00007fbd4365de18 @limit=4, @precision=nil, @range=-2147483648...2147483648, @scale=nil>,
# "author_name"=>#<ActiveModel::Type::String:0x00007fbd4363bb38 @false="f", @limit=nil, @precision=nil, @scale=nil, @true="t">,
# "council"=>#<ActiveModel::Type::String:0x00007fbd4363bb38 @false="f", @limit=nil, @precision=nil, @scale=nil, @true="t">,
# "licit"=>#<ActiveModel::Type::Boolean:0x00007fbd4365d3f0 @limit=nil, @precision=nil, @scale=nil>,
# "meta"=>#<ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb:0x00007fbd4365cc70 @limit=nil, @precision=nil, @scale=nil>}
#
#   def attribute_types
#      binding.pry
      #Tiun.attribute_types_for(self).attribute_map.reduce({}) {|ats, a| ats.merge(a.name => a.type)}
#      super
#      @_tiun_attribute_types ||= Tiun.attribute_types_for(self) || super
#   end

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

   #TODO
   #defaults fields: :user
   #  tiun as: :branch /as: :is
   #  include user(without *_at)/all fields (to list/form),
   #  all scopes (to list),
   #  all havings - has_many/ones (to form)
   # tiunable_by :field/s - for text search by this field/s
end

Model = Tiun::Model
