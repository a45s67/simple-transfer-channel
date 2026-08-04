# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# importmap does not pin ActiveStorage by default. Use the asset shipped with the
# gem rather than a CDN. We construct DirectUpload by hand from a Stimulus
# controller, so ActiveStorage.start() is unnecessary -- we only need the class.
pin "@rails/activestorage", to: "activestorage.esm.js"
pin_all_from "app/javascript/controllers", under: "controllers"
