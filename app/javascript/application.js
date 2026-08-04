// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
// DirectUpload is constructed by hand in dropzone_controller; this import just
// makes sure the module is loaded. ActiveStorage.start() is not needed -- we
// have no form fields carrying data-direct-upload-url.
import "@rails/activestorage"
