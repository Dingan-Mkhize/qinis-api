module Api
  module V1
    class SessionsController < ApplicationController
      def create
        user = User.find_by(email: params[:email].to_s.strip.downcase)

        unless user&.valid_password?(params[:password].to_s)
          return render json: { error: "Invalid email or password." }, status: :unauthorized
        end

        user.reset_authentication_token!
        render json: { token: user.authentication_token, user: user_payload(user) }, status: :ok
      end

      def destroy
        user = authenticate_from_token
        user&.update_column(:authentication_token, nil)
        head :no_content
      end

      private

      def user_payload(user)
        { id: user.id, email: user.email }
      end
    end
  end
end
