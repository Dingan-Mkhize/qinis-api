module Export
  class PdfBeatBoardService
    ACT_LABELS = {
      "act_1"    => "ACT 1",
      "act_2a"   => "ACT 2A",
      "midpoint" => "MIDPOINT",
      "act_2b"   => "ACT 2B",
      "act_3"    => "ACT 3"
    }.freeze

    ACT_COLORS = {
      "act_1"        => { header: "2C5F8A", light: "D6E8F5" },
      "act_2a"       => { header: "2E7D4B", light: "D4EDE0" },
      "midpoint"     => { header: "1B7B8A", light: "CCE8EC" },
      "act_2b"       => { header: "5C2D91", light: "E5D8F5" },
      "act_3"        => { header: "C0392B", light: "F9D8D6" },
      "foundational" => { header: "B8860B", light: "FFF3CC" }
    }.freeze

    def initialize(project)
      @project = project
      @bible   = StoryBibleService.new(project).read_bible
    end

    def call
      pdf = Prawn::Document.new(page_size: "A4", margin: [36, 36, 36, 36])
      render_header(pdf)
      render_beats(pdf)
      pdf.render
    end

    private

    def render_header(pdf)
      pdf.fill_color "1A1A1A"
      pdf.text @project.title, size: 22, style: :bold
      pdf.move_down 8

      logline    = @bible["logline"].to_s.strip
      word_count = @bible["logline_word_count"].to_i
      if logline.present?
        pdf.fill_color "555555"
        pdf.text "LOGLINE: #{logline} (#{word_count} words)", size: 9, style: :italic
        pdf.move_down 4
      end

      pdf.fill_color "000000"
      pdf.stroke_color "CCCCCC"
      pdf.stroke_horizontal_rule
      pdf.stroke_color "000000"
      pdf.move_down 18
    end

    def render_beats(pdf)
      BeatBoardService::ACT_ZONES.each do |zone|
        cards = placed_cards_for_zone(zone)
        next if cards.empty?

        pdf.start_new_page if pdf.cursor < 60
        render_zone_header(pdf, zone)
        cards.each { |card| render_card(pdf, card, zone) }
        pdf.move_down 10
      end
    end

    def render_zone_header(pdf, zone)
      colors = ACT_COLORS.fetch(zone, ACT_COLORS["act_1"])
      label  = ACT_LABELS.fetch(zone, zone.upcase)
      top    = pdf.cursor

      pdf.fill_color colors[:header]
      pdf.fill_rectangle [0, top], pdf.bounds.width, 24
      pdf.fill_color "FFFFFF"
      pdf.text_box label, at: [8, top - 6], width: pdf.bounds.width - 16, size: 12, style: :bold
      pdf.fill_color "000000"
      pdf.move_down 32
    end

    def render_card(pdf, card, zone)
      colors = card["card_type"] == "foundational" ? ACT_COLORS["foundational"] : ACT_COLORS.fetch(zone, ACT_COLORS["act_1"])
      body   = card["body"].to_s.strip.presence || "[No content]"
      num    = card["beat_number"]
      label  = num ? "#{num}. #{card["title"].upcase}" : card["title"].upcase

      body_h = [safe_height(pdf, body, pdf.bounds.width - 16, 9) + 14, 30].max
      total  = 20 + body_h + 8

      pdf.start_new_page if pdf.cursor < total + 10

      top = pdf.cursor

      pdf.fill_color colors[:header]
      pdf.fill_rectangle [0, top], pdf.bounds.width, 20
      pdf.fill_color "FFFFFF"
      pdf.text_box label,
                   at: [6, top - 5], width: pdf.bounds.width - 12,
                   size: 9, style: :bold, overflow: :shrink_to_fit

      body_top = top - 20
      pdf.fill_color colors[:light]
      pdf.fill_rectangle [0, body_top], pdf.bounds.width, body_h
      pdf.fill_color "222222"
      pdf.text_box body,
                   at: [8, body_top - 5], width: pdf.bounds.width - 16,
                   height: body_h - 8, size: 9, overflow: :shrink_to_fit

      pdf.fill_color "000000"
      pdf.move_down total
    end

    def safe_height(pdf, text, width, size)
      pdf.height_of(text.presence || " ", width: width, size: size)
    rescue StandardError
      lines = (text.length.to_f / [ width / (size * 0.55), 1 ].max).ceil + text.count("\n") + 1
      lines * size * 1.2
    end

    def placed_cards_for_zone(zone)
      Array(@project.beat_board&.dig("cards"))
        .select { |c| c["act"] == zone && c["placed"] }
        .sort_by { |c| c["position"].to_i }
    end
  end
end
