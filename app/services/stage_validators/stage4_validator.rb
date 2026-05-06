module StageValidators
  class Stage4Validator
    # Rule-based only — logline presence check. No Claude call.
    def self.run(project, checker)
      [
        checker.run_check("logline_presence", retryable: false) do |_attempt|
          bible   = StoryBibleService.new(project).read_bible
          logline = bible["logline"].to_s.strip

          logline.present? ? [] : ["Logline is required before advancing"]
        end
      ]
    end
  end
end
