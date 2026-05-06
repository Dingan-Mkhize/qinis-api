class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :projects, dependent: :destroy

  before_create :set_authentication_token

  def reset_authentication_token!
    update_column(:authentication_token, generate_token)
  end

  private

  def set_authentication_token
    self.authentication_token ||= generate_token
  end

  def generate_token
    loop do
      token = SecureRandom.urlsafe_base64(32)
      break token unless User.exists?(authentication_token: token)
    end
  end
end
