class TestMailer < ApplicationMailer
  def hello_world
    @message = "Hello, world"
    recipient = params.fetch(:recipient, "user@example.com")

    mail from: "test@example.com", to: recipient do |format|
      format.html { render inline: "<h1><%= @message %></h1>" }
      format.text { render inline: "<%= @message %>" }
    end
  end
end