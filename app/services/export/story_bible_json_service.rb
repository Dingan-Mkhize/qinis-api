module Export
  class StoryBibleJsonService
    def initialize(project)
      @project = project
    end

    def call
      JSON.pretty_generate(@project.story_bible || {})
    end
  end
end
