# frozen_string_literal: true

# SEEDS ------------------------------------------------------------------------

[
  ["user@example.com", "tok_visa"],
  ["user-bad-source@example.com", "tok_chargeCustomerFail"]
].each do |(email, stripe_source)|
  User.find_or_create_by!(
    email: email,
    stripe_customer_id: stripe_source
  )
end

# MOCKS ------------------------------------------------------------------------

module Stripe
  class CardError < StandardError; end

  class StripeError < StandardError; end

  class Charge
    # :nocov:
    def self.create(params, _args)
      raise CardError.new("Your card was declined.") if params[:customer] == "tok_chargeCustomerFail"

      charge_struct = Struct.new(:id)
      charge_struct.new(123)
    end
    # :nocov:
  end
end
