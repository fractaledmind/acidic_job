# frozen_string_literal: true

require "noticed"

class Notification < ApplicationRecord
  include Noticed::Model
end
