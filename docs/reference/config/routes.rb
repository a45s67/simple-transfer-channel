# 參考實作 — 未執行過,以 SPEC.md 為準
Rails.application.routes.draw do
  root "sessions#new"

  post   "/login",  to: "sessions#create",  as: :login
  delete "/logout", to: "sessions#destroy", as: :logout

  scope "/c/:name", constraints: { name: /[a-z0-9][a-z0-9_\-]{1,31}/ } do
    get    "/",                       to: "channels#show",  as: :channel
    post   "/items",                  to: "items#create",   as: :channel_items
    delete "/items/:id",              to: "items#destroy",  as: :channel_item
    get    "/items/:id/download",     to: "items#download", as: :download_channel_item
  end

  namespace :admin do
    root "sessions#new"
    post   "/login",  to: "sessions#create",  as: :login
    delete "/logout", to: "sessions#destroy", as: :logout
    resources :channels, only: [ :index, :create, :destroy ]
  end
end
