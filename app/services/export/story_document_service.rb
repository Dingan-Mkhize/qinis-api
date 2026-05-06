module Export
  class StoryDocumentService
    ACT_LABELS = {
      "act_1"    => "ACT 1",
      "act_2a"   => "ACT 2A",
      "midpoint" => "MIDPOINT",
      "act_2b"   => "ACT 2B",
      "act_3"    => "ACT 3"
    }.freeze

    def initialize(project)
      @project = project
      @bible   = StoryBibleService.new(project).read_bible
    end

    def call
      pdf = Prawn::Document.new(page_size: "A4", margin: [50, 50, 50, 50])
      render_cover(pdf)
      render_logline(pdf)
      render_protagonist(pdf)
      render_core_engine(pdf)
      render_antagonist(pdf)
      render_character_system(pdf)
      render_beat_board(pdf)
      pdf.render
    end

    private

    def render_cover(pdf)
      pdf.move_down 80
      pdf.fill_color "1A1A1A"
      pdf.text @project.title, size: 28, style: :bold, align: :center
      pdf.move_down 10
      pdf.fill_color "666666"
      pdf.text "Story Document", size: 14, align: :center
      pdf.move_down 6
      pdf.fill_color "999999"
      pdf.text "Generated #{Date.today.strftime("%-d %B %Y")}", size: 10, align: :center
      pdf.fill_color "000000"
      pdf.start_new_page
    end

    def render_logline(pdf)
      section_header(pdf, "LOGLINE")

      logline    = @bible["logline"].to_s.strip
      word_count = @bible["logline_word_count"].to_i
      amber      = @bible["logline_amber"]

      pdf.fill_color "111111"
      pdf.text logline.presence || "[No logline entered]", size: 11, style: :italic
      pdf.move_down 4
      pdf.fill_color amber ? "B8860B" : "888888"
      pdf.text "#{word_count} words#{amber ? " — over 30-word target" : ""}", size: 8
      pdf.fill_color "000000"
      pdf.move_down 24
    end

    def render_protagonist(pdf)
      section_header(pdf, "PROTAGONIST")
      prot = @bible.fetch("protagonist", {})

      type_num = prot["enneagram_type"]
      type_lbl = prot["enneagram_label"].to_s

      field_row(pdf, "Name",                    prot["name"].to_s.presence || "—")
      field_row(pdf, "Enneagram Type",           type_num ? "#{type_num} — #{type_lbl}" : "—")
      field_row(pdf, "Psychological Impediment", prot["psychological_impediment"].to_s.presence || "—")
      field_row(pdf, "Core Need",                prot["core_need"].to_s.presence || "—")
      pdf.move_down 24
    end

    def render_core_engine(pdf)
      section_header(pdf, "CORE STORY ENGINE")
      engine     = @bible.fetch("core_story_engine", {})
      story_type = @bible["story_type"].to_s.capitalize

      field_row(pdf, "Immediate Want",    engine["immediate_want"].to_s.presence || "—")
      field_row(pdf, "Catalyst",          engine["catalyst"].to_s.presence || "—")
      field_row(pdf, "Strength",          engine["strength"].to_s.presence || "—")
      field_row(pdf, "The Reversal",      engine["the_reversal"].to_s.presence || "—")
      field_row(pdf, "The Conflict",      engine["the_conflict"].to_s.presence || "—")
      field_row(pdf, "Obligatory Moment", engine["obligatory_moment"].to_s.presence || "—")
      field_row(pdf, "Defining Choice",   engine["defining_choice"].to_s.presence || "—")
      field_row(pdf, "The Resolution",    engine["the_resolution"].to_s.presence || "—")
      field_row(pdf, "Story Type",        story_type.presence || "—")
      pdf.move_down 24
    end

    def render_antagonist(pdf)
      section_header(pdf, "ANTAGONIST")
      ant  = @bible.fetch("antagonist", {})
      kind = ant["antagonist_kind"].to_s

      field_row(pdf, "Kind", kind.presence || "—")

      if %w[person combination].include?(kind)
        type_num = ant["enneagram_type"]
        type_lbl = ant["enneagram_label"].to_s
        field_row(pdf, "Name",                     ant["name"].to_s.presence || "—")
        field_row(pdf, "Enneagram Type",            type_num ? "#{type_num} — #{type_lbl}" : "—")
        field_row(pdf, "Core Fear",                 ant["core_fear"].to_s.presence || "—")
        field_row(pdf, "Core Desire",               ant["core_desire"].to_s.presence || "—")
        field_row(pdf, "Dynamic with Protagonist",  ant["dynamic"].to_s.presence || "—")
      end

      if %w[force combination].include?(kind)
        field_row(pdf, "Force Name",        ant["force_name"].to_s.presence || "—")
        field_row(pdf, "Force Description", ant["force_description"].to_s.presence || "—")
      end

      if kind == "internal"
        field_row(pdf, "Internal Opposition", ant["internal_description"].to_s.presence || "—")
      end

      pdf.move_down 24
    end

    def render_character_system(pdf)
      section_header(pdf, "CHARACTER SYSTEM")
      slots = Array(@bible.dig("characters", "slots")).select { |s| s["filled"] }

      if slots.empty?
        pdf.fill_color "888888"
        pdf.text "No characters added.", size: 9
        pdf.fill_color "000000"
      else
        slots.each do |slot|
          name = slot["name"].to_s.presence || "Unnamed"
          subsection_header(pdf, "#{slot["type_number"]} / #{slot["type_label"]} — #{name}")
          field_row(pdf, "Role",        slot["role"].to_s.presence || "—")
          field_row(pdf, "Core Fear",   slot["core_fear"].to_s.presence || "—")
          field_row(pdf, "Core Desire", slot["core_desire"].to_s.presence || "—")
          field_row(pdf, "Dynamic",     slot["dynamic"].to_s.presence || "—")
          pdf.move_down 8
        end
      end

      relational_map = @bible.dig("characters", "relational_map").to_s.strip
      if relational_map.present?
        subsection_header(pdf, "Relational Map")
        pdf.fill_color "111111"
        pdf.text relational_map, size: 9
        pdf.fill_color "000000"
        pdf.move_down 8
      end

      pdf.move_down 16
    end

    def render_beat_board(pdf)
      pdf.start_new_page
      section_header(pdf, "BEAT BOARD")

      BeatBoardService::ACT_ZONES.each do |zone|
        cards = placed_cards_for_zone(zone)
        next if cards.empty?

        pdf.move_down 12
        pdf.fill_color "444444"
        pdf.text ACT_LABELS.fetch(zone, zone.upcase), size: 10, style: :bold
        pdf.fill_color "000000"
        pdf.stroke_color "DDDDDD"
        pdf.stroke_horizontal_rule
        pdf.stroke_color "000000"
        pdf.move_down 10

        cards.each do |card|
          pdf.start_new_page if pdf.cursor < 80
          num   = card["beat_number"]
          title = card["title"].to_s
          body  = card["body"].to_s.strip.presence || "[No content]"

          pdf.fill_color "111111"
          pdf.text (num ? "#{num}. #{title}" : title), size: 10, style: :bold
          pdf.move_down 4
          pdf.fill_color "333333"
          pdf.text body, size: 9
          pdf.fill_color "000000"
          pdf.move_down 12
        end
      end
    end

    # ── Layout helpers ───────────────────────────────────────────────────────────

    def section_header(pdf, text)
      pdf.fill_color "1A1A1A"
      pdf.text text, size: 14, style: :bold
      pdf.stroke_color "333333"
      pdf.stroke_horizontal_rule
      pdf.stroke_color "000000"
      pdf.fill_color "000000"
      pdf.move_down 12
    end

    def subsection_header(pdf, text)
      pdf.fill_color "333333"
      pdf.text text, size: 10, style: :bold
      pdf.fill_color "000000"
      pdf.move_down 4
    end

    def field_row(pdf, label, value)
      pdf.move_down 4
      pdf.formatted_text [
        { text: "#{label}: ", styles: [ :bold ], size: 9, color: "333333" },
        { text: value.to_s,   size: 9,           color: "111111" }
      ]
    end

    def placed_cards_for_zone(zone)
      Array(@project.beat_board&.dig("cards"))
        .select { |c| c["act"] == zone && c["placed"] }
        .sort_by { |c| c["position"].to_i }
    end
  end
end
