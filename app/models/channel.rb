class Channel < ApplicationRecord
  MIN_PASSWORD_LENGTH = 8

  # Starts with a lowercase alphanumeric, then alphanumerics / - / _, 2-32 total
  NAME_FORMAT = /\A[a-z0-9][a-z0-9_\-]{1,31}\z/
  # Same thing as a route constraint (no \A \z)
  NAME_ROUTE_CONSTRAINT = /[a-z0-9][a-z0-9_\-]{1,31}/

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

  private

  def normalize_name
    self.name = self.class.normalize(name)
  end
end
