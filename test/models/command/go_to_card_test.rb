require "test_helper"

class Command::GoToCardTest < ActionDispatch::IntegrationTest
  include CommandTestHelper

  include VcrTestHelper

  setup do
    @card = cards(:logo)
  end

  test "redirect to the card perma" do
    result = execute_command "#{@card.id}"

    assert_equal @card, result.url
  end

  test "result in a regular search if the card does not exist" do
    command = parse_command "123"

    assert command.valid?

    result = command.execute
    assert_equal 1, result.size
    assert_equal search_path(q: "123"), result.first.url
  end
end
