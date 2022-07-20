# frozen_string_literal: true

class User < ApplicationRecord
  has_many :notifications, as: :recipient

  validates :email, presence: true
  validates :stripe_customer_id, presence: true
end
