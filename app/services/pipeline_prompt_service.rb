class PipelinePromptService
  MODEL        = "claude-sonnet-4-6"
  TIMEOUT      = 30
  TOKEN_BUDGET = 2_000

  PRUNING_RULES = [
    "Strip all _source metadata fields — LLM sees values only, not provenance",
    "Strip genre_expectations hash — summarise as single line under genre_context if populated, delete if empty",
    "Strip characters.relational_map if over 200 tokens — replace with placeholder note and compress slot entries to type_label + role + truncated dynamic",
    "Strip beat_board.cards body text — retain beat_number, title, and act only",
    "If Bible JSON still exceeds TOKEN_BUDGET after above passes, reduce characters.slots to type_label and role only"
  ].freeze

  def initialize(project)
    @project = project
  end

  # Reads and prunes the Bible, wraps it in constraint tags, builds stage/field
  # prompts (stubs for now), and calls Claude. Returns response text or nil on
  # any failure — never raises.
  def generate(stage, field, input_context = {})
    bible      = StoryBibleService.new(@project).read_bible
    pruned     = prune(bible)
    constraints = wrap_constraints(pruned)

    token_est = estimate_tokens(constraints)
    if token_est > TOKEN_BUDGET
      Rails.logger.warn(
        "[PipelinePromptService] Bible injection ~#{token_est} tokens exceeds " \
        "#{TOKEN_BUDGET}-token budget (stage=#{stage} field=#{field})"
      )
    end

    system_prompt = build_system_prompt(stage, field, constraints, input_context)
    user_message  = build_user_message(stage, field, input_context)

    call_api(system_prompt, user_message)
  rescue => e
    Rails.logger.error("[PipelinePromptService] generate raised #{e.class}: #{e.message}")
    nil
  end

  private

  # ── Pruning ───────────────────────────────────────────────────────────────

  def prune(bible)
    b = strip_source_keys(bible)
    prune_genre_expectations!(b)
    prune_relational_map!(b)
    prune_beat_board!(b)
    prune_slots_if_over_budget!(b)
    b
  end

  # Recursively remove every key that ends in "_source".
  def strip_source_keys(value)
    case value
    when Hash
      value
        .reject { |k, _| k.to_s.end_with?("_source") }
        .transform_values { |v| strip_source_keys(v) }
    when Array
      value.map { |v| strip_source_keys(v) }
    else
      value
    end
  end

  # Replace the full genre_expectations hash with a single summary line.
  # Deleted entirely when empty — it adds no constraint value.
  def prune_genre_expectations!(b)
    exp = b.delete("genre_expectations")
    return unless exp.is_a?(Hash) && exp.present?

    genres = Array(b["genre"]).join(", ")
    b["genre_context"] = genres.present? ? "Genre constraints active for: #{genres}" : "[genre constraints established]"
  end

  # If the relational map exceeds 200 tokens it is replaced with a placeholder
  # and each slot entry is reduced to its structurally relevant fields.
  def prune_relational_map!(b)
    map = b.dig("characters", "relational_map")
    return unless map.present? && estimate_tokens(map) > 200

    b["characters"]["relational_map"] = "[relational map compressed — see slot dynamics below]"
    b["characters"]["slots"] = Array(b.dig("characters", "slots")).map do |slot|
      {
        "type_label" => slot["type_label"],
        "role"       => slot["role"],
        "dynamic"    => slot["dynamic"].to_s.truncate(80)
      }
    end
  end

  # Retain only structural metadata for beat cards — strip body text entirely.
  def prune_beat_board!(b)
    cards = b.dig("beat_board", "cards")
    return unless cards.is_a?(Array)

    b["beat_board"]["cards"] = cards.map { |c| c.slice("beat_number", "title", "act") }
  end

  # Final safety pass: if JSON is still over budget, reduce character slots to
  # type + role only — the minimum needed to convey ensemble composition.
  def prune_slots_if_over_budget!(b)
    return unless estimate_tokens(b.to_json) > TOKEN_BUDGET
    return unless b.dig("characters", "slots").is_a?(Array)

    b["characters"]["slots"] = b["characters"]["slots"].map do |slot|
      slot.slice("type_label", "role")
    end
  end

  # ── Constraint wrapping ───────────────────────────────────────────────────

  def wrap_constraints(pruned)
    <<~BLOCK.strip
      <story_bible_constraints>
      ESTABLISHED STORY DECISIONS — INVIOLABLE CONSTRAINTS
      #{pruned.to_json}
      </story_bible_constraints>
    BLOCK
  end

  # ── Prompt construction ───────────────────────────────────────────────────

  def build_system_prompt(stage, field, constraint_block, _input_context)
    base = "#{constraint_block}\n\n" \
           "You are a story structure assistant for QINIS Script. " \
           "Respond with the requested content only — no preamble, no explanation, no alternatives unless asked."

    hard = stage == "core_story_engine" ? stage3_hard_constraint(field) : nil
    hard.present? ? "#{base}\n\n#{hard}" : base
  end

  def build_user_message(stage, field, input_context)
    return stage3_user_message(field, input_context) if stage.to_s == "core_story_engine"

    "Generate content for stage=#{stage} field=#{field}."
  end

  # ── Stage 3 — Core Story Engine ───────────────────────────────────────────

  # Hard constraints appended to the system prompt for fields that need tight
  # output control. Nil return means no constraint for that field.
  def stage3_hard_constraint(field)
    case field.to_s
    when "strength"
      "Respond with a single phrase of no more than 15 words. Do not elaborate."
    when "the_set_up"
      "Maximum 200 words."
    when "crossing_the_threshold"
      "Maximum 200 words."
    when "the_ordeal"
      "This is the 75% mark. Describe what HAPPENS, not what the protagonist CHOOSES. The choice comes in The Reward. Maximum 200 words."
    when "the_reward"
      "This is the Defining Choice. The protagonist makes a decision. Do not describe the outcome — that belongs in The New World. Maximum 200 words."
    when "the_new_world"
      "This is the final state. Show the protagonist after everything has resolved. Maximum 200 words."
    end
  end

  def stage3_user_message(field, ctx)
    story_type = ctx[:story_type].to_s

    case field.to_s
    when "ordinary_world"
      "Describe the protagonist's ordinary world before the story begins. Show who they are, " \
      "what their life looks like, and what is missing or broken beneath the surface."

    when "the_theme"
      "State the thematic question this story is asking. This is the central human question " \
      "the protagonist's journey will answer — not the plot question."

    when "the_set_up"
      "Describe the setup. Establish the protagonist's situation and the conditions that make " \
      "them susceptible to The Call. Show what HAPPENS before anything changes."

    when "the_call"
      "Describe the call to adventure. What external event arrives that asks the protagonist " \
      "to step outside their ordinary world? This must happen TO the protagonist."

    when "the_refusal"
      "Describe the protagonist's initial resistance to The Call. Connect the refusal directly " \
      "to their Psychological Impediment."

    when "crossing_the_threshold"
      "Describe the moment the protagonist commits to the journey. What is the single point of " \
      "no return that locks them into the story? Show the event — do not describe its aftermath."

    when "strength"
      "Propose the exact opposite of the protagonist's Psychological Impediment as a single phrase. " \
      "This is what the protagonist will move toward (Comedy) or fail to reach (Tragedy)."

    when "the_turning_point"
      "Describe the turning point at the midpoint of the second act. Something fundamental shifts — " \
      "the protagonist's approach, their understanding, or the stakes. This is a pivot, not a setback."

    when "the_ordeal"
      if story_type == "tragedy"
        "Describe the protagonist's highest point — the apparent triumph at 75% of the story. " \
        "They appear to have succeeded, but this is the ultimate manifestation of their flaw."
      else
        "Describe the protagonist's lowest point at 75% of the story. Everything they wanted is " \
        "lost or inverted. This is the darkest moment before the final act."
      end

    when "the_reward"
      if story_type == "tragedy"
        "Describe the decision the protagonist makes when they are at their apparent peak. " \
        "They double down on their flaw. Do not describe what happens next."
      else
        "Describe the decision the protagonist makes when they are at their lowest. " \
        "What choice shows them moving toward their Strength? Do not describe the outcome."
      end

    when "the_new_world"
      "Describe the new status quo after the Defining Choice plays out. Show the protagonist " \
      "in their final state — what has changed, what has been lost, what has been gained."

    else
      "Generate content for stage=core_story_engine field=#{field}."
    end
  end

  # ── API call ─────────────────────────────────────────────────────────────

  def call_api(system_prompt, user_message)
    api_key = ENV["ANTHROPIC_API_KEY"]
    if api_key.blank?
      Rails.logger.error("[PipelinePromptService] ANTHROPIC_API_KEY is not set")
      return nil
    end

    conn = Faraday.new(url: "https://api.anthropic.com") do |f|
      f.request  :json
      f.response :json, content_type: /\bjson\b/
      f.options.timeout      = TIMEOUT
      f.options.open_timeout = 10
    end

    resp = conn.post("/v1/messages") do |req|
      req.headers["x-api-key"]         = api_key
      req.headers["anthropic-version"] = "2023-06-01"
      req.body = {
        model:      MODEL,
        max_tokens: 1_024,
        system:     system_prompt,
        messages:   [{ role: "user", content: user_message }]
      }
    end

    if resp.success?
      resp.body.dig("content", 0, "text")
    else
      Rails.logger.error("[PipelinePromptService] Claude API #{resp.status}: #{resp.body}")
      nil
    end
  rescue Faraday::TimeoutError => e
    Rails.logger.error("[PipelinePromptService] Claude API timeout: #{e.message}")
    nil
  rescue Faraday::Error => e
    Rails.logger.error("[PipelinePromptService] Faraday error #{e.class}: #{e.message}")
    nil
  end

  # ── Utilities ─────────────────────────────────────────────────────────────

  # Rough token estimate: ~4 characters per token (GPT/Claude rule of thumb).
  def estimate_tokens(text)
    text.to_s.length / 4
  end
end
