# 參考實作 — 未執行過,以 SPEC.md 為準
#
# GOTCHAS.md 第 5 條:broadcast 的 partial 沒有 controller context。
# _item.html.erb 只能吃 item 這個 local。
class Item < ApplicationRecord
  KINDS = %w[file text].freeze

  belongs_to :channel
  has_one_attached :file, dependent: :purge_later

  validates :kind, inclusion: { in: KINDS }
  validates :body, presence: true, if: :text?
  validate  :file_must_be_attached, if: :file?

  scope :alive, -> {
    where("expires_at IS NULL OR expires_at > ?", Time.current)
  }

  after_create_commit  -> { broadcast_prepend_to channel, target: "items", partial: "items/item" }
  after_destroy_commit -> { broadcast_remove_to channel }

  def file? = kind == "file"
  def text? = kind == "text"

  def self.default_expires_at
    days = ENV.fetch("DEFAULT_TTL_DAYS", "7").to_i
    days.positive? ? days.days.from_now : nil
  end

  private

  def file_must_be_attached
    errors.add(:file, "must be attached") unless file.attached?
  end
end
