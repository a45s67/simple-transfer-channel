class Channel < ApplicationRecord
  MIN_PASSWORD_LENGTH = 8

  # Starts with a lowercase alphanumeric, then alphanumerics / - / _, 2-32 total
  NAME_FORMAT = /\A[a-z0-9][a-z0-9_\-]{1,31}\z/
  # Same thing as a route constraint (no \A \z)
  NAME_ROUTE_CONSTRAINT = /[a-z0-9][a-z0-9_\-]{1,31}/

  # The curl API's credential. It is a signed message, not a stored secret:
  # there is nothing to keep in the database and nothing to revoke, because it
  # stops verifying five minutes after it was minted. Rotating one is just
  # minting the next.
  DEFAULT_API_TOKEN_TTL_MINUTES = 5
  API_UPLOAD = "u"
  API_DOWNLOAD = "d"

  has_secure_password

  has_many :items, dependent: :destroy

  before_validation :normalize_name

  validates :name, presence: true, uniqueness: true, format: { with: NAME_FORMAT }
  validates :password, length: { minimum: MIN_PASSWORD_LENGTH }, if: -> { password.present? }

  # Always look up by the normalized name: "Lab1" and "lab1" are the same channel.
  def self.by_name(name)
    find_by(name: normalize(name))
  end

  def self.normalize(name)
    name.to_s.strip.downcase
  end

  # ENV is read at call time, not at load time -- tests need to override it.
  def self.api_token_ttl
    ENV.fetch("API_TOKEN_TTL_MINUTES", DEFAULT_API_TOKEN_TTL_MINUTES.to_s).to_i.minutes
  end

  # url_safe is not optional: the token is a path segment, and the default
  # Base64 alphabet contains "/" and "+". JSON keeps the payload Marshal-free.
  def self.api_verifier
    ActiveSupport::MessageVerifier.new(
      Rails.application.key_generator.generate_key("channel_api_v1", 32),
      digest: "SHA256", serializer: JSON, url_safe: true
    )
  end

  # Returns nil for anything that doesn't verify: tampered, expired, minted for
  # the other action, or pointing at a channel that has since been deleted.
  def self.from_api_token(token, action)
    data = api_verifier.verified(token.to_s)
    return nil unless data.is_a?(Hash) && data["act"] == action

    find_by(id: data["cid"])
  end

  # `action` is API_UPLOAD or API_DOWNLOAD. A download link that leaks cannot be
  # used to push files into the channel, and vice versa.
  def api_token(action)
    self.class.api_verifier.generate(
      { "cid" => id, "act" => action }, expires_in: self.class.api_token_ttl
    )
  end

  private

  def normalize_name
    self.name = self.class.normalize(name)
  end
end
