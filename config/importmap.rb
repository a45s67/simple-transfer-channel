# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# importmap 預設不會 pin ActiveStorage。用 gem 自帶的資產,不依賴 CDN。
# 我們是從 Stimulus controller 手動 new DirectUpload(...),所以不需要
# ActiveStorage.start(),只要能 import DirectUpload 這個 class。
pin "@rails/activestorage", to: "activestorage.esm.js"
pin_all_from "app/javascript/controllers", under: "controllers"
