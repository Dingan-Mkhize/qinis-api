class BeatBoardService
  # The 15 QINIS Native structural beats in canonical order.
  BEAT_TEMPLATES = [
    { beat_number: 1,  title: "The Ordinary World",       act: "act_1",  card_type: "structural"   },
    { beat_number: 2,  title: "The Theme",                act: "act_1",  card_type: "structural"   },
    { beat_number: 3,  title: "The Set-Up",               act: "act_1",  card_type: "foundational" },
    { beat_number: 4,  title: "The Call",                 act: "act_1",  card_type: "structural"   },
    { beat_number: 5,  title: "The Refusal",              act: "act_1",  card_type: "structural"   },
    { beat_number: 6,  title: "Crossing the Threshold",   act: "act_1",  card_type: "foundational" },
    { beat_number: 7,  title: "Tests, Allies, Enemies",   act: "act_2a", card_type: "structural"   },
    { beat_number: 8,  title: "The Approach",             act: "act_2a", card_type: "structural"   },
    { beat_number: 9,  title: "The Turning Point",        act: "act_2a", card_type: "structural"   },
    { beat_number: 10, title: "The Ordeal",               act: "act_2b", card_type: "foundational" },
    { beat_number: 11, title: "The Reckoning",            act: "act_2b", card_type: "structural"   },
    { beat_number: 12, title: "The Reward",               act: "act_2b", card_type: "foundational" },
    { beat_number: 13, title: "The Road Back",            act: "act_2b", card_type: "structural"   },
    { beat_number: 14, title: "The Return",               act: "act_3",  card_type: "structural"   },
    { beat_number: 15, title: "The New World",            act: "act_3",  card_type: "foundational" }
  ].freeze

  ACT_ZONES          = %w[act_1 act_2a act_2b act_3].freeze
  FOUNDATIONAL_BEATS = [3, 6, 10, 12, 15].freeze
  STRUCTURAL_BEATS   = [1, 2, 4, 5, 7, 8, 9, 11, 13, 14].freeze

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
    foundational     = tmpl[:card_type] == "foundational"
    premise_prefill  = !foundational && [1, 2].include?(tmpl[:beat_number])

    body = if foundational
             foundational_body(tmpl[:beat_number], bible)
           elsif premise_prefill
             structural_prefill(tmpl[:beat_number], bible)
           else
             ""
           end

    {
      "id"          => SecureRandom.uuid,
      "beat_number" => tmpl[:beat_number],
      "title"       => tmpl[:title],
      "body"        => body,
      "body_source" => (foundational || premise_prefill) ? "bible" : "manual",
      "act"         => tmpl[:act],
      "card_type"   => tmpl[:card_type],
      "position"    => index,
      "placed"      => foundational || premise_prefill
    }
  end

  private_class_method def self.foundational_body(beat_number, bible)
    cse = bible.dig("core_story_engine") || {}
    case beat_number
    when 3  then cse["the_set_up"].to_s
    when 6  then cse["crossing_the_threshold"].to_s
    when 10 then cse["the_ordeal"].to_s
    when 12 then cse["the_reward"].to_s
    when 15 then cse["the_new_world"].to_s
    else ""
    end
  end

  private_class_method def self.structural_prefill(beat_number, bible)
    premise = bible.dig("premise") || {}
    case beat_number
    when 1 then premise["dramatic_situation"].to_s
    when 2 then premise["central_question"].to_s
    else ""
    end
  end

  # Deep copy via JSON round-trip so mutations to the returned array
  # do not affect the original beat_board attribute.
  private_class_method def self.copy_cards(project)
    JSON.parse(Array(project.beat_board&.dig("cards")).to_json)
  end
end
