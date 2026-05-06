module Api
  module V1
    class ProjectsController < ApplicationController
      before_action :authenticate_user!
      before_action :set_project, only: %i[show destroy]

      def index
        projects = current_user.projects.order(updated_at: :desc)
        render json: projects.map { |p| project_summary(p) }
      end

      def create
        project = current_user.projects.build(project_params)
        StoryBibleService.new(project).initialize_bible

        if project.save
          render json: project_payload(project), status: :created
        else
          render json: { errors: project.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def show
        render json: project_payload(@project)
      end

      def destroy
        @project.destroy!
        head :no_content
      rescue ActiveRecord::RecordNotDestroyed => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def set_project
        @project = current_user.projects.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Project not found." }, status: :not_found
      end

      def project_params
        params.permit(:title)
      end

      def project_summary(project)
        {
          id:            project.id,
          title:         project.title,
          current_stage: project.current_stage,
          updated_at:    project.updated_at.iso8601
        }
      end

      def project_payload(project)
        {
          id:                 project.id,
          title:              project.title,
          current_stage:      project.current_stage,
          story_bible:        project.story_bible,
          beat_board:         project.beat_board,
          pipeline_data:      project.pipeline_data,
          logline:            project.logline,
          logline_word_count: project.logline_word_count,
          logline_amber:      project.logline_amber,
          story_type:         project.story_type,
          bible_version:      project.bible_version,
          lock_version:       project.lock_version,
          created_at:         project.created_at.iso8601,
          updated_at:         project.updated_at.iso8601
        }
      end
    end
  end
end
