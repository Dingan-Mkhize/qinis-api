module Api
  module V1
    class PipelineController < ApplicationController
      before_action :authenticate_user!
      before_action :set_project

      STAGE_ORDER = %w[
        premise protagonist core_story_engine logline
        character_system beat_board export
      ].freeze

      # POST /api/v1/pipeline/:project_id/advance
      #
      # Transaction boundary per spec:
      #   - StoryBibleService.write_stage_data and ConsistencyChecker run OUTSIDE the transaction
      #     (consistency checker may call Claude; Bible write mutates the in-memory project
      #      so validators see the new values).
      #   - All DB writes (pipeline_data, story_bible, history, consistency_log,
      #     current_stage) commit in a single transaction via save!.
      def advance
        stage = @project.current_stage

        if params[:stage].present? && params[:stage].to_s != stage
          return render json: { error: "Stage mismatch. Expected '#{stage}', got '#{params[:stage]}'." },
                        status: :conflict
        end

        if @project.export?
          return render json: { error: "Pipeline is already complete." }, status: :unprocessable_entity
        end

        apply_lock_version
        data       = stage_permitted_data(stage)
        next_stage = STAGE_ORDER[STAGE_ORDER.index(stage) + 1]

        # Outside transaction — mutates in-memory attributes only, never calls save.
        StoryBibleService.new(@project).write_stage_data(stage, data)
        check_result = ConsistencyChecker.check(stage, @project)

        # Single transaction: all writes committed atomically.
        Project.transaction do
          @project.pipeline_data = (@project.pipeline_data || {}).merge(stage => data)
          StoryBibleService.new(@project).append_history(stage, "commit")
          BeatBoardService.initialize_board(@project) if next_stage == "beat_board"
          @project.current_stage = next_stage
          @project.save!
        end

        render json: pipeline_response(@project, check_result)
      rescue ActiveRecord::StaleObjectError
        render json: { error: "Project was modified by another session. Please refresh." }, status: :conflict
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      rescue => e
        Rails.logger.error("[Pipeline#advance] #{e.class}: #{e.message}")
        render json: { error: "Failed to advance stage." }, status: :internal_server_error
      end

      # POST /api/v1/pipeline/:project_id/generate
      #
      # Calls PipelinePromptService for a single field. Stateless — never writes to DB.
      # stage param defaults to current_stage; pass explicitly for revision-mode generation.
      def generate
        stage   = params[:stage].presence&.to_s || @project.current_stage
        field   = params[:field].to_s.strip
        context = params.to_unsafe_h.fetch("context", nil)&.to_h || {}

        return render json: { error: "field is required." }, status: :unprocessable_entity if field.blank?

        result = PipelinePromptService.new(@project).generate(stage, field, context)

        if result
          render json: { result: result }
        else
          render json: { error: "Generation failed. Please try again or type manually." },
                 status: :unprocessable_entity
        end
      rescue => e
        Rails.logger.error("[Pipeline#generate] #{e.class}: #{e.message}")
        render json: { error: "Generation failed. Please try again or type manually." },
               status: :internal_server_error
      end

      # GET /api/v1/pipeline/:project_id/current
      def current
        render json: current_stage_response(@project)
      end

      # POST /api/v1/pipeline/:project_id/revise
      #
      # Only available after the full pipeline is complete (current_stage == export).
      # Sets current_stage back to the revised stage and returns downstream amber flags
      # so the frontend can surface which later stages may need review.
      def revise
        unless @project.export?
          return render json: { error: "Revision is only available after the full pipeline is complete." },
                        status: :unprocessable_entity
        end

        target = params[:stage].to_s
        unless STAGE_ORDER.include?(target) && target != "export"
          return render json: { error: "Invalid stage for revision: '#{target}'." }, status: :unprocessable_entity
        end

        apply_lock_version
        data = stage_permitted_data(target)

        # Outside transaction — same boundary as advance.
        StoryBibleService.new(@project).write_stage_data(target, data)
        check_result = ConsistencyChecker.check(target, @project)

        downstream = STAGE_ORDER.slice((STAGE_ORDER.index(target) + 1)..-1).reject { |s| s == "export" }

        Project.transaction do
          @project.pipeline_data = (@project.pipeline_data || {}).merge(target => data)
          StoryBibleService.new(@project).append_history(target, "revision")
          @project.current_stage = target
          @project.save!
        end

        render json: pipeline_response(@project, check_result).merge(downstream_amber: downstream)
      rescue ActiveRecord::StaleObjectError
        render json: { error: "Project was modified by another session. Please refresh." }, status: :conflict
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      rescue => e
        Rails.logger.error("[Pipeline#revise] #{e.class}: #{e.message}")
        render json: { error: "Failed to revise stage." }, status: :internal_server_error
      end

      private

      def set_project
        @project = current_user.projects.find(params[:project_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Project not found." }, status: :not_found
      end

      def apply_lock_version
        @project.lock_version = params[:lock_version].to_i if params[:lock_version].present?
      end

      # Explicit permit list for core_story_engine; all other stages use permit! since
      # their fields land in story_bible JSONB and carry no SQL injection risk.
      def stage_permitted_data(stage)
        return {} unless params[:data].present?

        if stage.to_s == "core_story_engine"
          return {} unless params[:data][:core_story_engine].present?

          params[:data][:core_story_engine].permit(
            :ordinary_world,               :ordinary_world_source,
            :the_theme,                    :the_theme_source,
            :the_set_up,                   :the_set_up_source,
            :the_call,                     :the_call_source,
            :the_refusal,                  :the_refusal_source,
            :crossing_the_threshold,       :crossing_the_threshold_source,
            :the_turning_point,            :the_turning_point_source,
            :the_ordeal,                   :the_ordeal_source,
            :the_reward,                   :the_reward_source,
            :the_new_world,                :the_new_world_source,
            :strength,                     :strength_source,
            :obligatory_moment_type
          ).to_h
        else
          params[:data].permit!.to_h
        end
      end

      def pipeline_response(project, check_result)
        {
          project:     project_payload(project),
          consistency: check_result
        }
      end

      def current_stage_response(project)
        {
          current_stage: project.current_stage,
          story_bible:   project.story_bible,
          beat_board:    project.beat_board,
          pipeline_data: project.pipeline_data,
          logline_amber: project.logline_amber,
          story_type:    project.story_type,
          lock_version:  project.lock_version
        }
      end

      def project_payload(project)
        {
          id:            project.id,
          current_stage: project.current_stage,
          story_bible:   project.story_bible,
          beat_board:    project.beat_board,
          logline_amber: project.logline_amber,
          story_type:    project.story_type,
          lock_version:  project.lock_version,
          updated_at:    project.updated_at.iso8601
        }
      end
    end
  end
end
