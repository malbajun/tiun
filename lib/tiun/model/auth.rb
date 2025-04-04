require 'tiun/model'

module Tiun::Model::Auth
   class InvalidTokenError < StandardError; end

   attr_reader :password, :password_confirmation

   def password_confirmation= value
      @password_confirmation = value
   end

   def password= value
      @password = value
   end

   def fill_in_encrypted_password
      self.encrypted_password = Tiun::Model::Auth.encrypt!(password) if password and quick_match_passwords?
   end

   def match_password? password
      self.encrypted_password == Tiun::Model::Auth.encrypt!(password)
   end

   def quick_match_passwords?
      password && password_confirmation && password == password_confirmation
   end

   def match_passwords?
      self.password && self.password == password_confirmation ||
         self.encrypted_password && (!password_confirmation || self.match_password?(password_confirmation))
   end

   def generate_session
      {
         session_token: Token::Session.create(tokenable: self),
         refresh_token: Token::Refresh.create(tokenable: self)
      }
   end

   def update_session token
      refresh_token =
         case token
         when Token::Refresh
            token
         when Token::Validate
            Token::Refresh.create(tokenable: self)
         when Hash
            Token::Refresh.actual.find_by_code(token["code"])
         when NilClass
            nil
         else
            raise(InvalidTokenError.new(token))
         end || Token::Refresh.create(tokenable: self)

      {
         session_token: Token::Session.create(tokenable: self),
         refresh_token: refresh_token
      }
   end

   def current_session token = nil
      refresh_token = Token::Refresh.find_by(tokenable: self)
      session_token = Token::Session.find_by(tokenable: self)

      { session_token: session_token, refresh_token: refresh_token }
   end

   def destroy_session token = nil
      refresh_token = Token::Refresh.find_by(tokenable: self)
      session_token = Token::Session.find_by(tokenable: self)

      { session_token: session_token.destroy, refresh_token: refresh_token.destroy }
   end

   class << self
      def encrypt! password
         OpenSSL::HMAC.hexdigest("SHA256", "salt", password)
      end

      def included kls
         kls.module_eval do
            has_many :accounts
            has_many :tokina, as: :tokenable

            validates_presence_of :encrypted_password
            validate :match_passwords?
            before_validation :fill_in_encrypted_password

            accepts_nested_attributes_for :accounts, reject_if: :all_blank, allow_destroy: true
         end
      end
   end
end

Model::Auth = Tiun::Model::Auth
