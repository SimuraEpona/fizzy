require "test_helper"

class Command::Ai::TranslatorTest < ActionDispatch::IntegrationTest
  include VcrTestHelper

  setup do
    @user = users(:david)
  end

  test "filter by assignments" do
    # List context
    assert_command({ context: { assignee_ids: [ "jz" ] } }, "cards assigned to jz")
    assert_command({ context: { assignee_ids: [ "kevin" ] } }, "stuff assigned to kevin")
    assert_command({ context: { assignee_ids: [ "jz" ] } }, "assigned to jz")
    assert_command({ context: { assignment_status: "unassigned" } }, "unassigned cards")
    assert_command({ context: { assignment_status: "unassigned" } }, "not assigned")
    assert_command({ context: { assignee_ids: [ "jorge" ], terms: [ "performance" ] } }, "cards about performance assigned to jorge")
    assert_command({ context: { closer_ids: [ "jz" ], indexed_by: "latest" } }, "stuff that jz has done lately")

    # Card context
    assert_command({ context: { assignee_ids: [ "jz" ] } }, "cards assigned to jz", context: :card)
  end

  test "filter by tag" do
    # List context
    assert_command({ context: { tag_ids: [ "design" ] } }, "cards tagged with design")
    assert_command({ context: { tag_ids: [ "design" ] } }, "cards tagged with #design")
    assert_command({ context: { tag_ids: [ "design" ] } }, "#design cards")

    # Card context
    assert_command({ context: { tag_ids: [ "design" ] } }, "cards tagged with design")
  end

  test "filter by indexed_by" do
    # List context
    assert_command({ context: { indexed_by: "closed" } }, "closed cards")
    assert_command({ context: { indexed_by: "closed" } }, "completed cards")
    assert_command({ context: { indexed_by: "closed" } }, "completed")

    assert_command({ context: { indexed_by: "newest" } }, "recent cards")
    assert_command({ context: { indexed_by: "latest" } }, "cards with recent activity")

    assert_command({ context: { indexed_by: "stalled" } }, "stalled cards")
    assert_command({ context: { indexed_by: "stalled" } }, "stagnated cards")
  end

  test "filter by stage" do
    assert_command({ context: { stage_ids: [ "uphill" ] } }, "cards in uphill")
    assert_command({ context: { stage_ids: [ "on hold" ] } }, "on hold cards")
  end

  test "filter by card id" do
    assert_command({ context: { card_ids: [ 123 ] } }, "card 123")
    assert_command({ context: { card_ids: [ 123, 456 ] } }, "card 123, 456")
    assert_command({ commands: [ "/search 123" ] }, "123") # Notice existing cards will be intercepted earlier
  end

  test "filter by time ranges" do
    assert_command({ context: { closure: "thisweek", indexed_by: "closed" } }, "cards completed this week")
    assert_command({ context: { creation: "thisweek", tag_ids: [ "design" ], creator_ids: [ "jz" ] } }, "cards created this week by jz tagged as #design")
    assert_command({ context: { creation: "thismonth", creator_ids: [ "gabriel", "michael" ] } }, "cards created by gabriel or michael this month")
  end

  test "acts on cards passing their ids" do
    assert_command({ context: { card_ids: [ 123, 456 ] }, commands: [ "/close" ] }, "close 123 and 456")
    assert_command({ context: { card_ids: [ 123 ] }, commands: [ "/close" ] }, "close 123")
    assert_command({ context: { card_ids: [ 1, 5, 9 ] }, commands: [ "/assign #{users(:david).to_gid}" ] }, "assign 1, 5 and 9 to myself")
  end

  test "filter by collections" do
    assert_command({ context: { collection_ids: [ "Writebook" ] } }, "writebook collection")
    assert_command({ context: { collection_ids: [ "basecamp 5" ] } }, "basecamp 5 collection")
    assert_command({ context: { collection_ids: [ "Writebook" ] } }, "writebook")
  end

  test "closing soon and falling back soon" do
    assert_command({ context: { indexed_by: "falling_back_soon" } }, "cards to be reconsidered soon")
    assert_command({ context: { assignee_ids: [ users(:david).to_gid.to_s ], indexed_by: "closing_soon" } }, "my cards that are going to be auto closed")
  end

  test "close cards" do
    # List context
    assert_command({ commands: [ "/close" ] }, "close")
    assert_command({ commands: [ "/close not now" ] }, "close as not now")
    assert_command({ context: { assignee_ids: [ "jz" ] }, commands: [ "/close" ] }, "close cards assigned to jz")

    # Card context
    assert_command({ commands: [ "/close" ] }, "close", context: :card)
  end

  test "reopen cards" do
    # List context
    assert_command({ commands: [ "/reopen" ] }, "reopen")
    assert_command({ context: { assignee_ids: [ "jz" ] }, commands: [ "/reopen" ] }, "reopen cards assigned to jz")
    assert_command({ context: { closure: "thisweek", indexed_by: "closed" }, commands: [ "/reopen" ] }, "reopen cards closed this week")

    # Card context
    assert_command({ commands: [ "/reopen" ] }, "reopen", context: :card)
  end

  test "assign cards" do
    # List context
    assert_command({ commands: [ "/assign jz" ] }, "assign to jz")
    assert_command({ context: { tag_ids: [ "design" ] }, commands: [ "/assign jz" ] }, "assign cards tagged with #design to jz", context: :card)
  end

  test "tag cards" do
    # List context
    assert_command({ commands: [ "/tag #design" ] }, "tag with #design")
  end

  test "move cards between considering and doing" do
    assert_command({ commands: [ "/consider" ] }, "consider")
    assert_command({ commands: [ "/consider" ] }, "move to consider")

    assert_command({ commands: [ "/do" ] }, "do")
    assert_command({ commands: [ "/do" ] }, "move to doing")
  end

  test "assign stages to card" do
    assert_command({ commands: [ "/stage in progress" ] }, "move to stage in progress")
    assert_command({ commands: [ "/stage in progress" ] }, "move to in progress")
  end

  test "visit screens" do
    assert_command({ commands: [ "/visit #{user_path(@user, script_name: nil)}" ] }, "my profile")
    assert_command({ commands: [ "/visit #{edit_user_path(@user, script_name: nil)}" ] }, "edit my profile")
    assert_command({ commands: [ "/visit #{account_settings_path(script_name: nil)}" ] }, "manage users")
    assert_command({ commands: [ "/visit #{account_settings_path(script_name: nil)}" ] }, "account settings")
  end

  test "view users profiles" do
    assert_command({ commands: [ "/user jz" ] }, "check what jz has been up to")
    assert_command({ commands: [ "/user kevin" ] }, "view kevin")
    assert_command({ commands: [ "/user john" ] }, "view john")
  end

  test "create cards" do
    assert_command({ commands: [ "/add" ] }, "add card")
    assert_command({ commands: [ "/add new task" ] }, "add card new task")
    assert_command({ commands: [ "/add" ] }, "create card")
    assert_command({ commands: [ "/add urgent issue" ] }, "create card urgent issue")
  end

  test "filter by closed by" do
    assert_command({ context: { closer_ids: [ users(:david).to_gid.to_s ], indexed_by: "closed" } }, "cards closed by me")
    assert_command({ context: { closure: "thisweek", closer_ids: [ "jorge", "kevin" ], indexed_by: "closed" } }, "cards closed by Jorge or kevin this week")
  end

  test "default to search" do
    assert_command({ commands: [ "/search backups" ] }, "backups")
    assert_command({ context: { terms: [ "backups" ] } }, "cards about backups")
  end

  test "combine commands and filters" do
    assert_command(
      { context: { card_ids: [ 176, 170 ] }, commands: [ "/do", "/assign #{users(:david).to_gid}", "/stage investigating" ] },
      "Move 176 and 170 to doing, assign to me and set the stage to Investigating")
    assert_command(
      { context: { tag_ids: [ "design" ] }, commands: [ "/assign andy", "/tag #v2" ] },
      "assign andy to the current #design cards and tag them with #v2")
    assert_command(
      { context: { assignee_ids: [ "andy" ] }, commands: [ "/close", "/assign kevin" ] },
      "close cards assigned to andy and assign them to kevin")
    assert_command(
      { context: { tag_ids: [ "design" ] }, commands: [ "/assign andy", "/tag #v2" ] },
      "assign cards tagged with #design to andy and tag them with #v2")
  end

  private
    def assert_command(expected, query, context: :list)
      assert_equal expected, translate(query, context:)
    end

    def translate(query, user: @user, context: :list)
      raise "Context must be :card or _list" unless context.in?(%i[ card list ])
      url = context == :card ? card_url(cards(:logo)) : cards_url
      context = Command::Parser::Context.new(user, url: url, script_name: integration_session.default_url_options[:script_name])
      translator = Command::Ai::Translator.new(context)
      translator.translate(query)
    end
end
