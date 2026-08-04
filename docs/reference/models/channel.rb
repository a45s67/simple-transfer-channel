# 參考實作 — 未執行過,以 SPEC.md 為準
class Channel < ApplicationRecord
  has_secure_password

  has_many :items, dependent: :destroy

  NAME_FORMAT = /\A[a-z0-9][a-z0-9_\-]{1,31}\z/

  before_validation :normalize_name

  validates :name, presence: true, uniqueness: true, format: { with: NAME_FORMAT }
  validates :password, length: { minimum: 8 }, if: -> { password.present? }

  private

  def normalize_name
    self.name = name.to_s.strip.downcase
  end
end
