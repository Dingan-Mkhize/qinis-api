class StoryBibleService
  def initialize(project)
    @project = project
  end

  def initialize_bible
    @project.story_bible = empty_bible
  end

  # Merges confirmed stage data (with source metadata) into the current Bible.
  # Stages whose fields live inside a named Bible sub-key (e.g. core_story_engine)
  # send flat params from the controller; wrap them here before deep-merging so they
  # land at the correct path rather than polluting the top level.
  NESTED_STAGES = %w[premise protagonist core_story_engine antagonist characters].freeze

  def write_stage_data(stage, data)
    overlay = NESTED_STAGES.include?(stage.to_s) ? { stage.to_s => data } : data
    @project.story_bible = deep_merge(read_bible, stringify_deep(overlay))
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
        "ordinary_world"                  => "",
        "ordinary_world_source"           => "manual",
        "the_theme"                       => "",
        "the_theme_source"                => "manual",
        "the_set_up"                      => "",
        "the_set_up_source"               => "manual",
        "the_call"                        => "",
        "the_call_source"                 => "manual",
        "the_refusal"                     => "",
        "the_refusal_source"              => "manual",
        "crossing_the_threshold"          => "",
        "crossing_the_threshold_source"   => "manual",
        "strength"                        => "",
        "strength_source"                 => "manual",
        "the_turning_point"               => "",
        "the_turning_point_source"        => "manual",
        "the_ordeal"                      => "",
        "the_ordeal_source"               => "manual",
        "obligatory_moment_type"          => nil,
        "the_reward"                      => "",
        "the_reward_source"               => "manual",
        "the_new_world"                   => "",
        "the_new_world_source"            => "manual"
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
