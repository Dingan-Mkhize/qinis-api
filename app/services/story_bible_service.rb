class StoryBibleService
  def initialize(project)
    @project = project
  end

  def initialize_bible
    @project.story_bible = empty_bible
  end

  # Merges confirmed stage data (with source metadata) into the current Bible.
  # data must mirror the Bible's key structure — nested hashes are deep-merged,
  # arrays and scalar values are replaced outright.
  def write_stage_data(_stage, data)
    @project.story_bible = deep_merge(read_bible, stringify_deep(data))
  end

  def read_bible
    @project.story_bible.presence || empty_bible
  end

  # Snapshots the current Bible and appends it to story_bible_history.
  # type is "commit" on first-run stage completion, "revision" on any later edit.
  def append_history(stage, type)
    entry = {
      "stage"        => stage.to_s,
      "type"         => type.to_s,
      "committed_at" => Time.current.iso8601,
      "snapshot"     => read_bible
    }
    @project.story_bible_history = Array(@project.story_bible_history) + [entry]
  end

  private

  def empty_bible
    {
      "genre"              => [],
      "genre_source"       => "manual",
      "genre_expectations" => {},
      "tone"               => [],
      "tone_source"        => "manual",
      "premise" => {
        "dramatic_situation"        => "",
        "dramatic_situation_source" => "manual",
        "stakes"                    => "",
        "stakes_source"             => "manual",
        "central_question"          => "",
        "central_question_source"   => "manual"
      },
      "protagonist" => {
        "name"                            => "",
        "name_source"                     => "manual",
        "psychological_impediment"        => "",
        "psychological_impediment_source" => "manual",
        "core_need"                       => "",
        "core_need_source"                => "manual",
        "enneagram_type"                  => nil,
        "enneagram_label"                 => ""
      },
      "core_story_engine" => {
        "immediate_want"           => "",
        "immediate_want_source"    => "manual",
        "catalyst"                 => "",
        "catalyst_source"          => "manual",
        "strength"                 => "",
        "strength_source"          => "manual",
        "the_reversal"             => "",
        "the_reversal_source"      => "manual",
        "the_conflict"             => "",
        "the_conflict_source"      => "manual",
        "obligatory_moment"        => "",
        "obligatory_moment_source" => "manual",
        "obligatory_moment_type"   => nil,
        "defining_choice"          => "",
        "defining_choice_source"   => "manual",
        "the_resolution"           => "",
        "the_resolution_source"    => "manual"
      },
      "story_type"         => nil,
      "logline"            => "",
      "logline_word_count" => 0,
      "logline_amber"      => false,
      "antagonist" => {
        "antagonist_kind"      => nil,
        "name"                 => "",
        "enneagram_type"       => nil,
        "enneagram_label"      => "",
        "core_fear"            => "",
        "core_desire"          => "",
        "dynamic"              => "",
        "force_name"           => "",
        "force_description"    => "",
        "internal_description" => ""
      },
      "characters" => {
        "slots"         => [],
        "relational_map" => ""
      }
    }
  end

  def deep_merge(base, overlay)
    base.merge(overlay) do |_key, old_val, new_val|
      old_val.is_a?(Hash) && new_val.is_a?(Hash) ? deep_merge(old_val, new_val) : new_val
    end
  end

  # Recursively stringify all keys so data passed with symbol keys merges correctly.
  def stringify_deep(value)
    case value
    when Hash  then value.transform_keys(&:to_s).transform_values { |v| stringify_deep(v) }
    when Array then value.map { |v| stringify_deep(v) }
    else            value
    end
  end
end
