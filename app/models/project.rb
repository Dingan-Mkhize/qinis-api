class Project < ApplicationRecord
  belongs_to :user

  enum :current_stage, {
    premise:           0,
    protagonist:       1,
    core_story_engine: 2,
    logline:           3,
    character_system:  4,
    beat_board:        5,
    export:            6
  }

  validates :title, presence: true
end
