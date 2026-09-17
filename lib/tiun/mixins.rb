require 'ostruct'

class Object
   def blank?
      case self
      when NilClass, FalseClass
         true
      when TrueClass
         false
      when Hash, Array
         !self.any?
      else
         self.to_s == ""
      end
   end

   def to_os
      if self.respond_to?(:to_h)
         if self.is_a?(OpenStruct)
            self
         else
            self.to_h.reduce(OpenStruct.new) do |os, (x, y)|
               os[x.to_s] = y.respond_to?(:map) && y.to_os || y

               os
            end
         end
      else
         OpenStruct.new("" => self)
      end
   end
end

class Hash
   def to_h *args
      self.reduce({}) do |res, (key, value_in)|
         value =
            case value_in
            when Hash, OpenStruct
               value_in.to_h
            when Array
               value_in.to_a
            else
               value_in
            end

         res.merge({key => value})
      end
   end
end

class Array
   def to_os
      self.map {|x| (x.is_a?(Hash) || x.is_a?(Array)) ? x.to_os : x }
   end

   def to_a
      self.map do |value|
         case value
         when Hash, OpenStruct
            value.to_h
         when Array
            value.to_a
         else
            value
         end
      end
   end
end

class OpenStruct
   def blank?
      self.to_h.keys.empty?
   end

   def merge other
      ::OpenStruct.new(self.to_os.deep_merge(other))
   end

   def map *args, &block
      res = self.class.new

      self.each_pair do |key, value|
         res[key] = block[key, value]
      end

      res
   end

   def reduce default = nil, &block
      res = default

      self.each_pair do |key, value|
         res = block[res, key, value]
      end

      res
   end

   def to_h *args
      self.reduce({}) do |res, key, value_in|
         value =
            case value_in
            when Hash, OpenStruct
               value_in.to_h
            when Array
               value_in.to_a
            else
               value_in
            end

         res.merge({key => value})
      end
   end


   # +deep_merge+ deeply merges the Open Struct hash structure with the +other_in+ enumerating it key by key.
   # +options+ are the options to change behaviour of the method. It allows two keys: :mode, and :dedup
   # :mode key can be :append, :prepend, or :replace, defaulting to :append, when mode is to append, it combines duplicated
   # keys' values into an array, when :prepend it prepends an other value before previously stored one unlike for :append mode,
   # when :replace it replace duplicate values with a last ones.
   # :dedup key can be true, or false. It allows to deduplicate values when appending or prepending values.
   # Examples:
   #    open_struct.deep_merge(other_open_struct)
   #    open_struct.deep_merge(other_open_struct, :prepend)
   #
   def deep_merge other_in, options_in = {}
      return self if other_in.nil? or other_in.blank?

      options = { mode: :replace }.merge(options_in)

      other =
         if other_in.is_a?(::OpenStruct)
            other_in.deep_dup
         elsif other_in.is_a?(::Hash)
            other_in.to_os
         else
            ::OpenStruct.new(nil => other_in.dup)
         end

      other.reduce(self.to_os.dup) do |res, key, value|
         res[key] =
            if res.table.keys.include?(key)
               case value
               when ::Hash
                  value.to_os.deep_merge(res[key].to_os, options).to_h.stringify_keys
               when ::OpenStruct
                  value.deep_merge(res[key].to_os, options)
               when ::Array
                  value | [res[key]].compact.flatten(1)
               when ::NilClass
                  res[key]
               else
                  value_out =
                     if options[:mode] == :append
                        [value, res[key]].compact.flatten(1).uniq
                     elsif options[:mode] == :prepend
                        [res[key], value].compact.flatten(1).uniq
                     else
                        value
                     end

                  if value_out.is_a?(Array) && options[:dedup]
                     value_out.uniq
                  else
                     value_out
                  end
               end
            else
               value
            end

         res
      end
   end
end

Mixins = Object
