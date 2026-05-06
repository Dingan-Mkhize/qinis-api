module StageValidators
  class Stage2Validator
    # Single Claude check — does the Psychological Impediment create a specific
    # causal connection to the Dramatic Situation?
    # Single pass only (retryable: false) per spec.
    def self.run(project, checker)
      [
        checker.run_check("impediment_premise_connection", retryable: false) do |attempt|
          bible      = StoryBibleService.new(project).read_bible
          impediment = bible.dig("protagonist", "psychological_impediment").to_s
          situation  = bible.dig("premise", "dramatic_situation").to_s

          next [] if impediment.blank? || situation.blank?

          response = PipelinePromptService.new(project).generate(
            :protagonist,
            :impediment_premise_connection,
            {
              attempt:            attempt,
              impediment:         impediment,
              dramatic_situation: situation,
              instruction:        "Does the Psychological Impediment create a specific causal connection to " \
                                  "the Dramatic Situation? Reply PASS or FAIL: <one-line reason>."
            }
          )

          # TODO: parse structured response once prompts are implemented
          parse_claude_response(response, "Impediment does not connect specifically to the dramatic situation")
        end
      ]
    end

    private_class_method def self.parse_claude_response(response, fallback_message)
      return [] if response.blank?
      return [] if response.strip.match?(/\APASS/i)
      [response.sub(/\AFAIL:\s*/i, "").strip.presence || fallback_message]
    end
  end
end
