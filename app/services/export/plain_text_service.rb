module Export
  class PlainTextService
    SEPARATOR = ("═" * 35).freeze

    ACT_LABELS = {
      "act_1"  => "ACT 1",
      "act_2a" => "ACT 2A",
      "act_2b" => "ACT 2B",
      "act_3"  => "ACT 3"
    }.freeze

    def initialize(project)
      @project = project
      @bible   = StoryBibleService.new(project).read_bible
    end

    def call
      lines = []
      lines << "TITLE: #{@project.title}"

      logline    = @bible["logline"].to_s.strip
      word_count = @bible["logline_word_count"].to_i
      lines << "LOGLINE: #{logline.presence || "[No logline]"} (#{word_count} words)"
      lines << ""
      lines << ""

      BeatBoardService::ACT_ZONES.each do |zone|
        cards = placed_cards_for_zone(zone)
        next if cards.empty?

        lines << SEPARATOR
        lines << ACT_LABELS.fetch(zone, zone.upcase)
        lines << SEPARATOR
        lines << ""

        cards.each do |card|
          num   = card["beat_number"]
          title = card["title"].to_s.upcase
          lines << (num ? "#{num}. #{title}" : title)
          body  = card["body"].to_s.strip
          lines << (body.present? ? body : "[No content]")
          lines << ""
        end
      end

      lines.join("\n")
    end

    private

    def placed_cards_for_zone(zone)
      Array(@project.beat_board&.dig("cards"))
        .select { |c| (c["column"].presence || c["act"]) == zone }
        .sort_by { |c| c["position"].to_i }
    end
  end
end
