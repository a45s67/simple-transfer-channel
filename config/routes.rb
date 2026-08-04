Rails.application.routes.draw do
  root "sessions#new"

  post   "/login",  to: "sessions#create",  as: :login
  delete "/logout", to: "sessions#destroy", as: :logout

  scope "/c/:name", constraints: { name: Channel::NAME_ROUTE_CONSTRAINT } do
    get    "/",                   to: "channels#show",  as: :channel
    post   "/items",              to: "items#create",   as: :channel_items
    delete "/items/:id",          to: "items#destroy",  as: :channel_item
    get    "/items/:id/download", to: "items#download", as: :download_channel_item
  end

  namespace :admin do
    root "sessions#new"
    post   "/login",  to: "sessions#create",  as: :login
    delete "/logout", to: "sessions#destroy", as: :logout
    resources :channels, only: [ :index, :create, :destroy ]
  end

  # ActiveStorage 的路由由我們自己畫(config.active_storage.draw_routes = false)。
  # 只留 direct upload 用得到的兩條:瀏覽器先 POST 拿 signed URL,再 PUT 檔案內容。
  # 所有 GET(blobs / representations / disk#show)刻意不畫 —— 那些只認 blob 的
  # signed_id、不認 session,會同時繞過不變量 1 與不變量 3。下載一律走 items#download。
  scope ActiveStorage.routes_prefix do
    post "/direct_uploads",      to: "active_storage/direct_uploads#create", as: :rails_direct_uploads
    put  "/disk/:encoded_token", to: "active_storage/disk#update",           as: :update_rails_disk_service
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
