module StageValidators
  class Stage3Validator
    def self.run(project, checker)
      [
        run_section_a(project, checker),
        *run_section_b(project, checker),
        *run_section_c(project, checker)
      ]
    end

    # ── Section A — rule-based ────────────────────────────────────────────
    # Does the Catalyst reference the Immediate Want situation?
    # No Claude call. Run on Section A Confirm.
    private_class_method def self.run_section_a(project, checker)
      checker.run_check("catalyst_references_immediate_want", retryable: false) do |_attempt|
        bible          = StoryBibleService.new(project).read_bible
        immediate_want = bible.dig("core_story_engine", "immediate_want").to_s.downcase
        catalyst       = bible.dig("core_story_engine", "catalyst").to_s.downcase

        next [] if immediate_want.blank? || catalyst.blank?

        # Extract words of 4+ chars as meaningful keywords; check any appear in catalyst.
        keywords    = immediate_want.scan(/\b\w{4,}\b/)
        referenced  = keywords.any? { |kw| catalyst.include?(kw) }

        referenced ? [] : ["Catalyst does not reference the Immediate Want situation"]
      end
    end

    # ── Section B — two parallel Claude checks ────────────────────────────
    # Both read the Bible independently. Run concurrently to halve latency.
    # Each allows one silent retry (retryable: true, MAX_ATTEMPTS = 2).
    private_class_method def self.run_section_b(project, checker)
      t_conflict = Thread.new do
        checker.run_check("conflict_tests_impediment", retryable: true) do |attempt|
          bible      = StoryBibleService.new(project).read_bible
          impediment = bible.dig("protagonist", "psychological_impediment").to_s
          conflict   = bible.dig("core_story_engine", "the_conflict").to_s

          next [] if impediment.blank? || conflict.blank?

          response = PipelinePromptService.new(project).generate(
            :core_story_engine,
            :conflict_tests_impediment,
            {
              attempt:    attempt,
              impediment: impediment,
              conflict:   conflict,
              instruction: "Does The Conflict directly test the protagonist's Psychological Impediment? " \
                           "Reply PASS or FAIL: <one-line reason>."
            }
          )

          # TODO: parse structured response once prompts are implemented
          parse_claude_response(response, "The Conflict does not directly test the Psychological Impediment")
        end
      end

      t_reversal = Thread.new do
        checker.run_check("reversal_delivers_want", retryable: true) do |attempt|
          bible          = StoryBibleService.new(project).read_bible
          immediate_want = bible.dig("core_story_engine", "immediate_want").to_s
          reversal       = bible.dig("core_story_engine", "the_reversal").to_s

          next [] if immediate_want.blank? || reversal.blank?

          response = PipelinePromptService.new(project).generate(
            :core_story_engine,
            :reversal_delivers_want,
            {
              attempt:       attempt,
              immediate_want: immediate_want,
              reversal:       reversal,
              instruction:    "Does The Reversal give the protagonist their Immediate Want? " \
                              "Reply PASS or FAIL: <one-line reason>."
            }
          )

          # TODO: parse structured response once prompts are implemented
          parse_claude_response(response, "The Reversal does not deliver the protagonist's Immediate Want")
        end
      end

      [t_conflict.value, t_reversal.value]
    end

    # ── Section C ─────────────────────────────────────────────────────────
    private_class_method def self.run_section_c(project, checker)
      bible        = StoryBibleService.new(project).read_bible
      story_type   = bible["story_type"].to_s
      strength     = bible.dig("core_story_engine", "strength").to_s.downcase
      def_choice   = bible.dig("core_story_engine", "defining_choice").to_s.downcase
      resolution   = bible.dig("core_story_engine", "the_resolution").to_s

      [
        # Rule-based: is Defining Choice consistent with Story Type?
        checker.run_check("defining_choice_story_type_alignment", retryable: false) do |_attempt|
          next [] if story_type.blank? || def_choice.blank?

          defining_choice_consistent?(story_type, strength, def_choice) ? [] :
            ["Defining Choice does not align with #{story_type.capitalize} story type"]
        end,

        # Claude: does Resolution flow from Defining Choice?
        checker.run_check("resolution_flows_from_defining_choice", retryable: true) do |attempt|
          next [] if def_choice.blank? || resolution.blank?

          response = PipelinePromptService.new(project).generate(
            :core_story_engine,
            :resolution_flows_from_defining_choice,
            {
              attempt:        attempt,
              defining_choice: def_choice,
              resolution:      resolution,
              story_type:      story_type,
              instruction:     "Does The Resolution flow naturally from the Defining Choice? " \
                               "Reply PASS or FAIL: <one-line reason>."
            }
          )

          # TODO: parse structured response once prompts are implemented
          parse_claude_response(response, "The Resolution does not flow from the Defining Choice")
        end
      ]
    end

    # Conservative keyword heuristic — only flags a clear contradiction.
    # Advisory amber, so false negatives are preferable to false positives.
    # Comedy: protagonist moves TOWARD Strength (growth/overcoming language).
    # Tragedy: protagonist moves AWAY from Strength (refusal/doubling-down language).
    private_class_method def self.defining_choice_consistent?(story_type, _strength, defining_choice)
      growth_markers  = %w[chooses overcomes learns realizes accepts changes grows embraces confronts]
      failure_markers = %w[refuses denies ignores rejects retreats clings doubles avoids escapes]

      growth_count  = growth_markers.count  { |w| defining_choice.include?(w) }
      failure_count = failure_markers.count { |w| defining_choice.include?(w) }

      case story_type.downcase
      when "comedy"
        # Only flag when failure language dominates with no growth language at all
        !(failure_count >= 2 && growth_count.zero?)
      when "tragedy"
        # Only flag when growth language dominates with no failure language at all
        !(growth_count >= 2 && failure_count.zero?)
      else
        true
      end
    end

    private_class_method def self.parse_claude_response(response, fallback_message)
      return [] if response.blank?
      return [] if response.strip.match?(/\APASS/i)
      [response.sub(/\AFAIL:\s*/i, "").strip.presence || fallback_message]
    end
  end
end
