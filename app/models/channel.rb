class Channel < ApplicationRecord
  MIN_PASSWORD_LENGTH = 8

  # 小寫英數開頭,其後可接英數 / - / _,總長 2–32
  NAME_FORMAT = /\A[a-z0-9][a-z0-9_\-]{1,31}\z/
  # route constraint 版本(不能有 \A \z)
  NAME_ROUTE_CONSTRAINT = /[a-z0-9][a-z0-9_\-]{1,31}/

  has_secure_password

  has_many :items, dependent: :destroy

  before_validation :normalize_name

  validates :name, presence: true, uniqueness: true, format: { with: NAME_FORMAT }
  validates :password, length: { minimum: MIN_PASSWORD_LENGTH }, if: -> { password.present? }

  # 名稱一律以正規化後的形式查詢,"Lab1" 和 "lab1" 是同一個 channel
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
