// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
// DirectUpload 由 dropzone_controller 手動建立,這裡只確保模組被載入。
// 不需要 ActiveStorage.start() —— 我們沒有用 data-direct-upload-url 的 form field。
import "@rails/activestorage"
