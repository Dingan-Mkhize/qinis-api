module StageValidators
  class Stage5Validator
    # Rule-based keyword/semantic presence check — no Claude call.
    # Does the antagonist dynamic reference the protagonist's Psychological Impediment?
    # Run on antagonist confirm. Advisory amber only.
    def self.run(project, checker)
      [
        checker.run_check("antagonist_dynamic_references_impediment", retryable: false) do |_attempt|
          bible      = StoryBibleService.new(project).read_bible
          impediment = bible.dig("protagonist", "psychological_impediment").to_s.downcase
          dynamic    = bible.dig("antagonist", "dynamic").to_s.downcase

          next [] if impediment.blank? || dynamic.blank?

          # Extract meaningful words (4+ chars) from impediment and check for presence in dynamic.
          keywords   = impediment.scan(/\b\w{4,}\b/).uniq
          referenced = keywords.any? { |kw| dynamic.include?(kw) }

          referenced ? [] : ["Antagonist dynamic does not reference the protagonist's Psychological Impediment"]
        end
      ]
    end
  end
end
