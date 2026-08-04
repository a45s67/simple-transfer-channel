# GOTCHAS.md 第 5 條:broadcast 的 partial 沒有 controller context,
# items/_item.html.erb 只能吃 item 這個 local。
class Item < ApplicationRecord
  KINDS = %w[file text].freeze

  DEFAULT_TTL_DAYS = 7
  DEFAULT_MAX_UPLOAD_MB = 2048

  belongs_to :channel
  has_one_attached :file, dependent: :purge_later

  validates :kind, inclusion: { in: KINDS }
  validates :body, presence: true, if: :text?
  validate :file_must_be_attached, if: :file?
  validate :file_size_within_limits, if: :file?

  scope :alive, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :expired, -> { where.not(expires_at: nil).where(expires_at: ..Time.current) }

  after_create_commit  -> { broadcast_prepend_to channel, target: "items", partial: "items/item" }
  after_destroy_commit -> { broadcast_remove_to channel }

  def file? = kind == "file"
  def text? = kind == "text"

  # ENV 在呼叫當下讀,不在載入時讀 —— 測試要能改。
  def self.default_expires_at
    days = ENV.fetch("DEFAULT_TTL_DAYS", DEFAULT_TTL_DAYS.to_s).to_i
    days.positive? ? days.days.from_now : nil
  end

  def self.max_upload_bytes
    ENV.fetch("MAX_UPLOAD_MB", DEFAULT_MAX_UPLOAD_MB.to_s).to_i.megabytes
  end

  private

  def file_must_be_attached
    errors.add(:file, "必須有附加檔案") unless file.attached?
  end

  def file_size_within_limits
    return unless file.attached?

    size = file.byte_size.to_i
    limit = self.class.max_upload_bytes

    if size.zero?
      errors.add(:file, "是空的(0 bytes)")
    elsif size > limit
      errors.add(:file, "超過上限 #{ActiveSupport::NumberHelper.number_to_human_size(limit)}")
    end
  end
end
