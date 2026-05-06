class ConsistencyChecker
  MAX_ATTEMPTS = 2

  # Entry point. Returns { valid: bool, conflicts: [], resolved: bool }.
  # Never raises — any uncaught error is logged and treated as passing so the
  # writer is never blocked by a checker failure.
  def self.check(stage, project)
    new(stage, project).run
  end

  def initialize(stage, project)
    @stage     = stage.to_s
    @project   = project
    @log_mutex = Mutex.new
  end

  def run
    results = dispatch
    aggregate(results)
  rescue => e
    Rails.logger.error("[ConsistencyChecker] stage=#{@stage} #{e.class}: #{e.message}")
    { valid: true, conflicts: [], resolved: true }
  end

  # Public so stage validators can call it directly.
  #
  # Runs a named check with optional retry:
  #   - Yields attempt number (1 or 2) to the block.
  #   - Block must return an Array of conflict strings (empty = passing).
  #   - If retryable: true and conflicts are found on attempt 1, retries once.
  #   - Logs every attempt to project.consistency_log.
  #   - surfaced_to_writer is set true only once the retry budget is exhausted.
  #
  # Usage:
  #   run_check("reversal_delivers_want", retryable: true) { |attempt| [...] }
  def run_check(check_name, retryable: true)
    attempt   = 1
    conflicts = []

    loop do
      conflicts = Array(yield(attempt))
      resolved  = conflicts.empty?

      log_event(
        check:              check_name,
        attempt:            attempt,
        conflicts:          conflicts,
        resolved:           resolved,
        surfaced_to_writer: !resolved && (!retryable || attempt >= MAX_ATTEMPTS)
      )

      break if resolved || !retryable || attempt >= MAX_ATTEMPTS
      attempt += 1
    end

    { valid: conflicts.empty?, conflicts: conflicts, resolved: conflicts.empty? }
  end

  private

  # Dispatches to the appropriate stage validator.
  # Validators receive the project and this checker instance so they can call
  # run_check directly and own their retry/logging behaviour.
  # Each validator returns an Array of result hashes.
  # Stage 1 (premise) is presence-only — no consistency check needed here.
  def dispatch
    case @stage
    when "protagonist"       then StageValidators::Stage2Validator.run(@project, self)
    when "core_story_engine" then StageValidators::Stage3Validator.run(@project, self)
    when "logline"           then StageValidators::Stage4Validator.run(@project, self)
    when "character_system"  then StageValidators::Stage5Validator.run(@project, self)
    when "beat_board"        then StageValidators::Stage6Validator.run(@project, self)
    else                          []
    end
  end

  # Merges an array of per-check result hashes into one top-level result.
  def aggregate(results)
    all_conflicts = Array(results).flat_map { |r| Array(r[:conflicts]) }
    {
      valid:     all_conflicts.empty?,
      conflicts: all_conflicts,
      resolved:  all_conflicts.empty?
    }
  end

  # Appends one entry to project.consistency_log per the spec schema.
  # Sets attributes only — never calls save.
  def log_event(check:, attempt:, conflicts:, resolved:, surfaced_to_writer:)
    entry = {
      "stage"              => @stage,
      "timestamp"          => Time.current.iso8601,
      "check"              => check.to_s,
      "attempt"            => attempt,
      "conflicts"          => Array(conflicts),
      "resolved"           => resolved,
      "surfaced_to_writer" => surfaced_to_writer
    }
    @log_mutex.synchronize do
      @project.consistency_log = Array(@project.consistency_log) + [entry]
    end
  end
end
