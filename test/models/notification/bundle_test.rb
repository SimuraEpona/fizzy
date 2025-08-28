require "test_helper"

class Notification::BundleTest < ActiveSupport::TestCase
  setup do
    @user = users(:david)
  end

  test "new notifications are bundled" do
    notification = assert_difference -> { @user.notification_bundles.pending.count }, 1 do
      @user.notifications.create!(source: events(:logo_published), creator: @user)
    end

    bundle = @user.notification_bundles.pending.last
    assert_includes bundle.notifications, notification
  end

  test "notifications are bundled withing the aggregation period" do
    notification_1 = assert_difference -> { @user.notification_bundles.pending.count }, 1 do
      @user.notifications.create!(source: events(:logo_published), creator: @user)
    end
    travel_to 3.hours.from_now

    notification_2 = assert_no_difference -> { @user.notification_bundles.count } do
      @user.notifications.create!(source: events(:logo_published), creator: @user)
    end
    travel_to 3.days.from_now

    notification_3 = assert_difference -> { @user.notification_bundles.pending.count }, 1 do
      @user.notifications.create!(source: events(:logo_published), creator: @user)
    end

    bundle_1, bundle_2 = @user.notification_bundles.last(2)
    assert_includes bundle_1.notifications, notification_1
    assert_includes bundle_1.notifications, notification_2
    assert_includes bundle_2.notifications, notification_3
  end

  test "overlapping bundles are invalid" do
    bundle_1 = @user.notification_bundles.create!(
      starts_at: Time.current,
      ends_at: 4.hours.from_now,
      status: :pending
    )

    bundle_2 = @user.notification_bundles.build(
      starts_at: 2.hours.from_now,
      ends_at: 6.hours.from_now,
      status: :pending
    )
    assert_not bundle_2.valid?

    # Bundle with overlapping end time should be invalid
    bundle_3 = @user.notification_bundles.build(
      starts_at: 2.hours.ago,
      ends_at: 2.hours.from_now,
      status: :pending
    )
    assert_not bundle_3.valid?

    # Bundle completely within another bundle should be invalid
    bundle_4 = @user.notification_bundles.build(
      starts_at: 1.hour.from_now,
      ends_at: 3.hours.from_now,
      status: :pending
    )
    assert_not bundle_4.valid?

    # Non-overlapping bundle should be valid
    bundle_5 = @user.notification_bundles.build(
      starts_at: 5.hours.from_now,
      ends_at: 9.hours.from_now,
      status: :pending
    )
    assert bundle_5.valid?
  end

  test "deliver_all delivers due bundles" do
    notification = @user.notifications.create!(source: events(:logo_published), creator: @user)

    bundle = @user.notification_bundles.pending.last

    assert bundle.pending?
    assert_includes bundle.notifications, notification

    bundle.update!(ends_at: 1.minute.ago)

    perform_enqueued_jobs only: Notification::Bundle::DeliverJob do
      Notification::Bundle.deliver_all
    end

    bundle.reload
    assert bundle.delivered?
  end

  test "deliver_all don't deliver bundles that are not due" do
    @user.notifications.create!(source: events(:logo_published), creator: @user)
    bundle = @user.notification_bundles.pending.last

    bundle.update!(ends_at: 1.minute.from_now)

    perform_enqueued_jobs only: Notification::Bundle::DeliverJob do
      Notification::Bundle.deliver_all
    end

    bundle.reload
    assert bundle.pending?
  end
end
