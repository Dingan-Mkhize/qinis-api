module StageValidators
  class Stage6Validator
    # Single batch Claude check — full beat board vs full Bible.
    # Reads all card body text and flags contradictions against established Bible decisions.
    # Amber flags on individual cards, never blocking. Single pass, no retry.
    def self.run(project, checker)
      [
        checker.run_check("beat_board_bible_consistency", retryable: false) do |attempt|
          cards  = Array(project.beat_board&.dig("cards"))
          filled = cards.select { |c| c["body"].to_s.present? }

          next [] if filled.empty?

          response = PipelinePromptService.new(project).generate(
            :beat_board,
            :bible_consistency_check,
            {
              attempt:      attempt,
              card_count:   filled.length,
              card_summary: filled.map { |c| { beat_number: c["beat_number"], title: c["title"], body: c["body"] } },
              instruction:  "Review all beat card body text against the Story Bible constraints. " \
                            "Reply PASS if no contradictions, or FAIL: <comma-separated list of specific contradictions>."
            }
          )

          # TODO: parse structured response once prompts are implemented
          parse_claude_response(response)
        end
      ]
    end

    private_class_method def self.parse_claude_response(response)
      return [] if response.blank?
      return [] if response.strip.match?(/\APASS/i)

      conflict_text = response.sub(/\AFAIL:\s*/i, "").strip
      return ["Beat board may contradict Bible decisions"] if conflict_text.blank?

      # Split comma-separated conflicts into individual entries
      conflict_text.split(/,\s*/).map(&:strip).reject(&:blank?)
    end
  end
end
