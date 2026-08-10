Rails.application.routes.draw do
  root "sessions#new"

  post   "/login",  to: "sessions#create",  as: :login
  delete "/logout", to: "sessions#destroy", as: :logout

  scope "/c/:name", constraints: { name: Channel::NAME_ROUTE_CONSTRAINT } do
    get    "/",                   to: "channels#show",  as: :channel
    get    "/api_urls",           to: "channels#api_urls", as: :channel_api_urls
    post   "/items",              to: "items#create",   as: :channel_items
    delete "/items/:id",          to: "items#destroy",  as: :channel_item
    get    "/items/:id/download", to: "items#download", as: :download_channel_item
  end

  # The curl API. The token in the path is the whole credential -- these actions
  # never look at the session (see Api::BaseController).
  #
  # format: false is required: without it "report.zip" splits into a filename
  # and a :format of "zip".
  scope "/api/c/:name", constraints: { name: Channel::NAME_ROUTE_CONSTRAINT }, format: false do
    put "/u/:token(/*filename)",     to: "api/items#create", as: :api_upload_channel_items
    get "/d/:token/:id(/*filename)", to: "api/items#show",   as: :api_download_channel_item
  end

  namespace :admin do
    root "sessions#new"
    post   "/login",  to: "sessions#create",  as: :login
    delete "/logout", to: "sessions#destroy", as: :logout
    resources :channels, only: [ :index, :create, :destroy ]
  end

  # We draw ActiveStorage's routes ourselves (config.active_storage.draw_routes = false).
  # Only the two a direct upload needs are kept: the browser POSTs for a signed
  # URL, then PUTs the file contents. Every GET (blobs / representations /
  # disk#show) is deliberately left undrawn -- those authenticate a blob's
  # signed_id and ignore the session, which would bypass invariants 1 and 3 at
  # once. All downloads go through items#download.
  scope ActiveStorage.routes_prefix do
    post "/direct_uploads",      to: "active_storage/direct_uploads#create", as: :rails_direct_uploads
    put  "/disk/:encoded_token", to: "active_storage/disk#update",           as: :update_rails_disk_service
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
