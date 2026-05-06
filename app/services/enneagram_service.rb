class EnneagramService
  ENNEAGRAM_TYPES = {
    1 => { label: "The Reformer",      core_fear: "Being corrupt or defective",           core_desire: "To be good and have integrity"              },
    2 => { label: "The Helper",        core_fear: "Being unloved or unwanted",             core_desire: "To be loved and appreciated"                },
    3 => { label: "The Achiever",      core_fear: "Being worthless or a failure",          core_desire: "To be valuable and admired"                 },
    4 => { label: "The Individualist", core_fear: "Having no identity or significance",    core_desire: "To find themselves and their significance"  },
    5 => { label: "The Investigator",  core_fear: "Being helpless or incompetent",         core_desire: "To be capable and competent"                },
    6 => { label: "The Loyalist",      core_fear: "Being without support or guidance",     core_desire: "To have security and support"               },
    7 => { label: "The Enthusiast",    core_fear: "Being trapped in pain or deprivation",  core_desire: "To be satisfied and content"                },
    8 => { label: "The Challenger",    core_fear: "Being controlled or harmed by others",  core_desire: "To protect themselves and be in control"    },
    9 => { label: "The Peacemaker",    core_fear: "Loss of connection and fragmentation",  core_desire: "To have inner stability and peace"          }
  }.freeze

  # Reads protagonist's Psychological Impediment and Core Need, calls Claude to
  # propose the primary Enneagram type plus an optional secondary type where two
  # are defensible. Returns a rationale of exactly two sentences.
  #
  # Returns:
  #   { primary_type: int, secondary_type: int|nil, rationale: string } or nil
  def self.propose_type(project)
    bible      = StoryBibleService.new(project).read_bible
    impediment = bible.dig("protagonist", "psychological_impediment").to_s
    core_need  = bible.dig("protagonist", "core_need").to_s

    return nil if impediment.blank? && core_need.blank?

    response = PipelinePromptService.new(project).generate(
      :character_system,
      :enneagram_type_proposal,
      {
        impediment:  impediment,
        core_need:   core_need,
        types:       types_summary,
        instruction: "Based on the Psychological Impediment and Core Need, identify the primary Enneagram type " \
                     "and optionally a secondary type if two are defensible. Provide a two-sentence rationale. " \
                     "Reply in exactly this format:\n" \
                     "PRIMARY: <1-9>\n" \
                     "SECONDARY: <1-9 or NONE>\n" \
                     "RATIONALE: <two sentences>"
      }
    )

    parse_type_proposal(response)
  end

  # Proposes a name and dramatic role for a supporting character of the given
  # Enneagram type, grounded in the project's story context.
  #
  # Returns: { name: string, role: string } or nil
  def self.generate_character_name_and_role(project, type_number)
    type_data = ENNEAGRAM_TYPES[type_number.to_i]
    return nil unless type_data

    bible = StoryBibleService.new(project).read_bible

    response = PipelinePromptService.new(project).generate(
      :character_system,
      :character_name_and_role,
      {
        type_number:  type_number,
        type_label:   type_data[:label],
        core_fear:    type_data[:core_fear],
        core_desire:  type_data[:core_desire],
        protagonist:  bible.fetch("protagonist", {}),
        instruction:  "Propose a name and a one-sentence dramatic role for a #{type_data[:label]} character " \
                      "that serves this specific story. Reply in exactly this format:\n" \
                      "NAME: <name>\n" \
                      "ROLE: <one sentence>"
      }
    )

    parse_name_and_role(response)
  end

  # Proposes a story-specific relationship dynamic between the given character
  # type and the protagonist. Reads protagonist type, impediment, core need, and
  # antagonist dynamic (if confirmed) as context.
  #
  # Returns: string or nil
  def self.generate_dynamic(project, character_type_number)
    type_data = ENNEAGRAM_TYPES[character_type_number.to_i]
    return nil unless type_data

    bible             = StoryBibleService.new(project).read_bible
    protagonist       = bible.fetch("protagonist", {})
    antagonist        = bible.fetch("antagonist", {})
    antagonist_dynamic = antagonist["dynamic"].to_s.presence

    response = PipelinePromptService.new(project).generate(
      :character_system,
      :character_dynamic,
      {
        character_type_number: character_type_number,
        character_type_label:  type_data[:label],
        character_core_fear:   type_data[:core_fear],
        character_core_desire: type_data[:core_desire],
        protagonist_type:      protagonist["enneagram_type"],
        protagonist_label:     protagonist["enneagram_label"].to_s,
        protagonist_impediment: protagonist["psychological_impediment"].to_s,
        protagonist_core_need:  protagonist["core_need"].to_s,
        antagonist_dynamic:     antagonist_dynamic,
        instruction:            "Propose a specific story-driven dynamic between this character and the protagonist. " \
                                "One to two sentences. Return only the dynamic text — no label, no heading."
      }
    )

    response.presence
  end

  # Reads all filled character slots against the full Bible and returns a single
  # cohesive paragraph describing dramatic chemistry across the ensemble.
  # Returns nil if no slots are filled (caller should not offer Generate yet).
  #
  # Returns: string or nil
  def self.generate_relational_map(project)
    bible = StoryBibleService.new(project).read_bible
    slots = Array(bible.dig("characters", "slots")).select { |s| s["filled"] }

    return nil if slots.empty?

    response = PipelinePromptService.new(project).generate(
      :character_system,
      :relational_map,
      {
        slot_count:  slots.length,
        slots:       slots.map { |s| s.slice("type_label", "name", "role", "dynamic") },
        instruction: "Write a single cohesive paragraph describing the dramatic chemistry of this ensemble. " \
                     "Show how these characters relate to each other and to the protagonist's journey. " \
                     "Return only the paragraph — no heading, no label."
      }
    )

    response.presence
  end

  # ── Private ───────────────────────────────────────────────────────────────

  private_class_method def self.parse_type_proposal(response)
    return nil if response.blank?

    primary_raw   = response[/PRIMARY:\s*(\d+)/i,   1]&.to_i
    secondary_raw = response[/SECONDARY:\s*(\d+)/i, 1]&.to_i
    secondary_raw = nil if response.match?(/SECONDARY:\s*NONE/i)
    rationale     = response[/RATIONALE:\s*(.+)/im, 1]&.strip

    # Validate both values fall within the 1-9 Enneagram range
    primary   = ENNEAGRAM_TYPES.key?(primary_raw)   ? primary_raw   : nil
    secondary = ENNEAGRAM_TYPES.key?(secondary_raw) ? secondary_raw : nil

    return nil unless primary

    secondary = nil if secondary == primary

    { primary_type: primary, secondary_type: secondary, rationale: rationale }
  end

  private_class_method def self.parse_name_and_role(response)
    return nil if response.blank?

    name = response[/NAME:\s*(.+)/i, 1]&.strip
    role = response[/ROLE:\s*(.+)/i, 1]&.strip

    return nil if name.blank?

    { name: name, role: role }
  end

  # One-line summary per type injected into the type-proposal prompt as context.
  private_class_method def self.types_summary
    ENNEAGRAM_TYPES.map { |num, t| "#{num}. #{t[:label]} — fear: #{t[:core_fear]}" }.join("\n")
  end
end
