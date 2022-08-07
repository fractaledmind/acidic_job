# frozen_string_literal: true
# # frozen_string_literal: true
#
# require "active_record"
# require "global_id"
# require "minitest/mock"
# require "logger"
# require "sqlite3"
# require "database_cleaner"
# require "noticed"
#

# DatabaseCleaner.clean_with(:truncation)
#
# DatabaseCleaner.clean_with(:deletion, except: %w[users])
#
# # SEEDS ------------------------------------------------------------------------
#
# USERS = [
#   ["user@example.com", "tok_visa"],
#   ["user-bad-source@example.com", "tok_chargeCustomerFail"]
# ].freeze
#
# USERS.each do |(email, stripe_source)|
#   User.create!(email: email,
#                stripe_customer_id: stripe_source)
# end
#
#
# # MOCKS ------------------------------------------------------------------------
#
# # module Stripe
# #   class CardError < StandardError; end
# #
# #   class StripeError < StandardError; end
# #
# #   class Charge
# #     def self.create(params, _args)
# #       raise CardError, "Your card was declined." if params[:customer] == "tok_chargeCustomerFail"
# #
# #       charge_struct = Struct.new(:id)
# #       charge_struct.new(123)
# #     end
# #   end
# # end
