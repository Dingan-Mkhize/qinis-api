class BeatBoardService
  # The 17 QINIS Native structural beats in canonical order.
  BEAT_TEMPLATES = [
    { beat_number: 1,  title: "Status Quo",              act: "act_1",    card_type: "foundational" },
    { beat_number: 2,  title: "Thematic Statement",      act: "act_1",    card_type: "foundational" },
    { beat_number: 3,  title: "Contextual Exposition",   act: "act_1",    card_type: "foundational" },
    { beat_number: 4,  title: "Catalyst",                act: "act_1",    card_type: "foundational" },
    { beat_number: 5,  title: "Deliberation",            act: "act_1",    card_type: "structural"   },
    { beat_number: 6,  title: "The Reversal",            act: "act_1",    card_type: "foundational" },
    { beat_number: 7,  title: "Relationship Initiation", act: "act_2a",   card_type: "structural"   },
    { beat_number: 8,  title: "Rising Action",           act: "act_2a",   card_type: "structural"   },
    { beat_number: 9,  title: "First Pressure Point",    act: "act_2a",   card_type: "structural"   },
    { beat_number: 10, title: "Midpoint",                act: "midpoint", card_type: "structural"   },
    { beat_number: 11, title: "Escalating Stakes",       act: "act_2b",   card_type: "structural"   },
    { beat_number: 12, title: "Second Pressure Point",   act: "act_2b",   card_type: "structural"   },
    { beat_number: 13, title: "The Obligatory Moment",   act: "act_2b",   card_type: "foundational" },
    { beat_number: 14, title: "Internalization",         act: "act_2b",   card_type: "structural"   },
    { beat_number: 15, title: "The Defining Choice",     act: "act_2b",   card_type: "foundational" },
    { beat_number: 16, title: "Climactic Action",        act: "act_3",    card_type: "structural"   },
    { beat_number: 17, title: "The Resolution",          act: "act_3",    card_type: "foundational" }
  ].freeze

  ACT_ZONES               = %w[act_1 act_2a midpoint act_2b act_3].freeze
  FOUNDATIONAL_BEATS      = [1, 2, 3, 4, 6, 13, 15, 17].freeze
  STRUCTURAL_BEATS        = [5, 7, 8, 9, 10, 11, 12, 14, 16].freeze

  # Builds the full beat board from the current Bible state.
  # Foundational cards are pre-populated; structural cards start unplaced (sidebar).
  # Sets project.beat_board — never calls save.
  def self.initialize_board(project)
    bible = StoryBibleService.new(project).read_bible
    cards = BEAT_TEMPLATES.map.with_index do |tmpl, index|
      build_initial_card(tmpl, bible, index)
    end
    project.beat_board = { "cards" => cards }
  end

  # Creates a new writer card in the given act zone.
  # Returns the new card hash (controller uses id for frontend response).
  def self.add_writer_card(project, title, act)
    cards    = copy_cards(project)
    last_pos = cards.select { |c| c["act"] == act.to_s }
                    .map { |c| c["position"] }
                    .max
                    .to_i
    new_card = {
      "id"          => SecureRandom.uuid,
      "beat_number" => nil,
      "title"       => title.to_s.strip,
      "body"        => "",
      "body_source" => "manual",
      "act"         => act.to_s,
      "card_type"   => "writer",
      "position"    => last_pos + 1,
      "placed"      => true
    }
    project.beat_board = { "cards" => cards + [new_card] }
    new_card
  end

  # Updates body text and source on any card. Returns the updated card or nil.
  def self.update_card_body(project, card_id, body, source = "manual")
    cards = copy_cards(project)
    card  = cards.find { |c| c["id"] == card_id }
    return nil unless card

    card["body"]        = body.to_s
    card["body_source"] = source.to_s
    project.beat_board  = { "cards" => cards }
    card
  end

  # Deletes writer cards only. Returns the deleted card for undo toast support,
  # or nil if the card is not found or is not a writer card.
  def self.delete_writer_card(project, card_id)
    cards = copy_cards(project)
    card  = cards.find { |c| c["id"] == card_id }
    return nil unless card
    return nil unless card["card_type"] == "writer"

    cards.reject! { |c| c["id"] == card_id }
    project.beat_board = { "cards" => cards }
    card
  end

  # Moves a card to a new 0-based index within its act zone.
  # Structural cards are locked to their assigned zone.
  # Writer cards may move to a different zone via new_act:.
  # Placing a structural card from the sidebar sets placed: true.
  def self.reorder_cards(project, card_id, new_position, new_act: nil)
    cards = copy_cards(project)
    card  = cards.find { |c| c["id"] == card_id }
    return project.beat_board if card.nil?

    card["placed"] = true if card["card_type"] == "structural"

    if new_act.present? && card["card_type"] == "writer"
      card["act"] = new_act.to_s
    end

    zone     = card["act"]
    siblings = cards.select { |c| c["act"] == zone && c["id"] != card_id }
                    .sort_by { |c| c["position"] }

    clamped  = new_position.to_i.clamp(0, siblings.length)
    siblings.insert(clamped, card)
    siblings.each_with_index { |c, i| c["position"] = i }

    project.beat_board = { "cards" => cards }
    card
  end

  # Returns all cards grouped by zone in canonical order, each zone sorted by position.
  def self.board_state(project)
    cards = copy_cards(project)
    ACT_ZONES.index_with do |zone|
      cards.select { |c| c["act"] == zone }.sort_by { |c| c["position"] }
    end
  end

  private

  private_class_method def self.build_initial_card(tmpl, bible, index)
    foundational = tmpl[:card_type] == "foundational"
    {
      "id"          => SecureRandom.uuid,
      "beat_number" => tmpl[:beat_number],
      "title"       => tmpl[:title],
      "body"        => foundational ? foundational_body(tmpl[:beat_number], bible) : "",
      "body_source" => foundational ? "bible" : "manual",
      "act"         => tmpl[:act],
      "card_type"   => tmpl[:card_type],
      "position"    => index,
      "placed"      => foundational
    }
  end

  private_class_method def self.foundational_body(beat_number, bible)
    case beat_number
    when 1
      bible.dig("premise", "dramatic_situation").to_s
    when 2
      bible.dig("premise", "central_question").to_s
    when 3
      name       = bible.dig("protagonist", "name").to_s.presence
      impediment = bible.dig("protagonist", "psychological_impediment").to_s.presence
      core_need  = bible.dig("protagonist", "core_need").to_s.presence
      [name, impediment, core_need].compact.join("\n\n")
    when 4
      bible.dig("core_story_engine", "catalyst").to_s
    when 6
      reversal = bible.dig("core_story_engine", "the_reversal").to_s.presence
      conflict = bible.dig("core_story_engine", "the_conflict").to_s.presence
      [reversal, conflict].compact.join("\n\n")
    when 13
      bible.dig("core_story_engine", "obligatory_moment").to_s
    when 15
      bible.dig("core_story_engine", "defining_choice").to_s
    when 17
      bible.dig("core_story_engine", "the_resolution").to_s
    else
      ""
    end
  end

  # Deep copy via JSON round-trip so mutations to the returned array
  # do not affect the original beat_board attribute.
  private_class_method def self.copy_cards(project)
    JSON.parse(Array(project.beat_board&.dig("cards")).to_json)
  end
end
