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
    # Does The Call reference The Set-Up situation?
    # No Claude call. Run on Section A Confirm.
    private_class_method def self.run_section_a(project, checker)
      checker.run_check("call_references_set_up", retryable: false) do |_attempt|
        bible    = StoryBibleService.new(project).read_bible
        set_up   = bible.dig("core_story_engine", "the_set_up").to_s.downcase
        the_call = bible.dig("core_story_engine", "the_call").to_s.downcase

        next [] if set_up.blank? || the_call.blank?

        # Extract words of 4+ chars as meaningful keywords; check any appear in the_call.
        keywords   = set_up.scan(/\b\w{4,}\b/)
        referenced = keywords.any? { |kw| the_call.include?(kw) }

        referenced ? [] : ["The Call does not reference The Set-Up situation"]
      end
    end

    # ── Section B — two parallel Claude checks ────────────────────────────
    # Both read the Bible independently. Run concurrently to halve latency.
    # Each allows one silent retry (retryable: true, MAX_ATTEMPTS = 2).
    private_class_method def self.run_section_b(project, checker)
      t_refusal = Thread.new do
        checker.run_check("threshold_tests_impediment", retryable: true) do |attempt|
          bible      = StoryBibleService.new(project).read_bible
          impediment = bible.dig("protagonist", "psychological_impediment").to_s
          the_refusal = bible.dig("core_story_engine", "the_refusal").to_s

          next [] if impediment.blank? || the_refusal.blank?

          response = PipelinePromptService.new(project).generate(
            :core_story_engine,
            :threshold_tests_impediment,
            {
              attempt:    attempt,
              impediment: impediment,
              the_refusal: the_refusal,
              instruction: "Does The Refusal reflect the protagonist's Psychological Impediment? " \
                           "Reply PASS or FAIL: <one-line reason>."
            }
          )

          # TODO: parse structured response once prompts are implemented
          parse_claude_response(response, "The Refusal does not reflect the protagonist's Psychological Impediment")
        end
      end

      t_threshold = Thread.new do
        checker.run_check("threshold_delivers_set_up", retryable: true) do |attempt|
          bible     = StoryBibleService.new(project).read_bible
          set_up    = bible.dig("core_story_engine", "the_set_up").to_s
          threshold = bible.dig("core_story_engine", "crossing_the_threshold").to_s
          impediment = bible.dig("protagonist", "psychological_impediment").to_s

          next [] if set_up.blank? || threshold.blank?

          response = PipelinePromptService.new(project).generate(
            :core_story_engine,
            :threshold_delivers_set_up,
            {
              attempt:    attempt,
              set_up:     set_up,
              threshold:  threshold,
              impediment: impediment,
              instruction: "Does Crossing the Threshold deliver the protagonist's Set-Up situation " \
                           "AND test their Psychological Impediment? " \
                           "Reply PASS or FAIL: <one-line reason>."
            }
          )

          # TODO: parse structured response once prompts are implemented
          parse_claude_response(response, "Crossing the Threshold does not deliver the Set-Up or test the Psychological Impediment")
        end
      end

      [t_refusal.value, t_threshold.value]
    end

    # ── Section C ─────────────────────────────────────────────────────────
    private_class_method def self.run_section_c(project, checker)
      bible      = StoryBibleService.new(project).read_bible
      story_type = bible["story_type"].to_s
      strength   = bible.dig("core_story_engine", "strength").to_s.downcase
      the_reward = bible.dig("core_story_engine", "the_reward").to_s.downcase
      new_world  = bible.dig("core_story_engine", "the_new_world").to_s

      [
        # Rule-based: is The Reward consistent with Story Type?
        checker.run_check("defining_choice_story_type_alignment", retryable: false) do |_attempt|
          next [] if story_type.blank? || the_reward.blank?

          defining_choice_consistent?(story_type, strength, the_reward) ? [] :
            ["The Reward does not align with #{story_type.capitalize} story type"]
        end,

        # Claude: does The New World flow from The Reward?
        checker.run_check("new_world_flows_from_reward", retryable: true) do |attempt|
          next [] if the_reward.blank? || new_world.blank?

          response = PipelinePromptService.new(project).generate(
            :core_story_engine,
            :new_world_flows_from_reward,
            {
              attempt:    attempt,
              the_reward: the_reward,
              new_world:  new_world,
              story_type: story_type,
              instruction: "Does The New World flow naturally from The Reward? " \
                           "Reply PASS or FAIL: <one-line reason>."
            }
          )

          # TODO: parse structured response once prompts are implemented
          parse_claude_response(response, "The New World does not flow from The Reward")
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
