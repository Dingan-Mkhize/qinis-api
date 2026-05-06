class ApplicationController < ActionController::API
  private

  def current_user
    @current_user ||= authenticate_from_token
  end

  def authenticate_user!
    render json: { error: "Unauthorized." }, status: :unauthorized unless current_user
  end

  def authenticate_from_token
    header = request.headers["Authorization"]
    return nil unless header&.start_with?("Bearer ")
    token = header.split(" ", 2).last.strip
    User.find_by(authentication_token: token)
  end
end
