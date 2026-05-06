Rails.application.routes.draw do
  devise_for :users

  namespace :api do
    namespace :v1 do
      resource  :sessions, only: %i[create destroy]

      resources :projects, only: %i[index create show destroy] do
        scope module: :projects do
          get "export/pdf_beat_board",   to: "exports#pdf_beat_board"
          get "export/text_beat_sheet",  to: "exports#text_beat_sheet"
          get "export/story_document",   to: "exports#story_document"
          get "export/story_bible_json", to: "exports#story_bible_json"
        end
      end

      scope "pipeline/:project_id" do
        post "advance",  to: "pipeline#advance"
        get  "current",  to: "pipeline#current"
        post "revise",   to: "pipeline#revise"
        post "generate", to: "pipeline#generate"
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
