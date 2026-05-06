module Api
  module V1
    module Projects
      class ExportsController < ApplicationController
        before_action :set_project

        def pdf_beat_board
          pdf = Export::PdfBeatBoardService.new(@project).call
          send_data pdf,
                    type:        "application/pdf",
                    disposition:  :attachment,
                    filename:    "#{filename_base}_beat_board.pdf"
        end

        def text_beat_sheet
          text = Export::PlainTextService.new(@project).call
          send_data text,
                    type:        "text/plain; charset=utf-8",
                    disposition:  :attachment,
                    filename:    "#{filename_base}_beat_sheet.txt"
        end

        def story_document
          pdf = Export::StoryDocumentService.new(@project).call
          send_data pdf,
                    type:        "application/pdf",
                    disposition:  :attachment,
                    filename:    "#{filename_base}_story_document.pdf"
        end

        def story_bible_json
          json = Export::StoryBibleJsonService.new(@project).call
          send_data json,
                    type:        "application/json; charset=utf-8",
                    disposition:  :attachment,
                    filename:    "#{filename_base}_story_bible.json"
        end

        private

        def set_project
          @project = Project.find(params[:project_id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Project not found" }, status: :not_found
        end

        def filename_base
          @project.title.parameterize(separator: "_").presence || "project_#{@project.id}"
        end
      end
    end
  end
end
