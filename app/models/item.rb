# The broadcast partial renders without controller context, so
# items/_item.html.erb may only rely on the `item` local.
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

  # Read ENV at call time, not at load time -- tests need to override it.
  def self.default_expires_at
    days = ENV.fetch("DEFAULT_TTL_DAYS", DEFAULT_TTL_DAYS.to_s).to_i
    days.positive? ? days.days.from_now : nil
  end

  def self.max_upload_bytes
    ENV.fetch("MAX_UPLOAD_MB", DEFAULT_MAX_UPLOAD_MB.to_s).to_i.megabytes
  end

  private

  def file_must_be_attached
    errors.add(:file, "must be attached") unless file.attached?
  end

  def file_size_within_limits
    return unless file.attached?

    size = file.byte_size.to_i
    limit = self.class.max_upload_bytes

    if size.zero?
      errors.add(:file, "is empty (0 bytes)")
    elsif size > limit
      errors.add(:file, "exceeds the #{ActiveSupport::NumberHelper.number_to_human_size(limit)} limit")
    end
  end
end
