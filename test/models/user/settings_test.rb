require "test_helper"

class User::SettingsTest < ActiveSupport::TestCase
  setup do
    @user = users(:david)
    @settings = @user.settings
  end

  test "changing the bundle email frequency to never will cancel pending bundles" do
    @settings.update!(bundle_email_frequency: :every_few_hours)
    bundle = @user.notification_bundles.create!
    @settings.update!(bundle_email_frequency: :never)
    assert_nil Notification::Bundle.find_by(id: bundle.id)
  end

  test "changing the bundle email frequency will deliver pending bundles" do
    bundle = @user.notification_bundles.create!
    assert bundle.pending?

    perform_enqueued_jobs only: Notification::Bundle::DeliverJob do
      @settings.update!(bundle_email_frequency: :daily)
    end

    assert bundle.reload.delivered?
  end

  test "changing other settings will not affect pending bundles" do
    bundle = @user.notification_bundles.create!

    perform_enqueued_jobs only: Notification::Bundle::DeliverJob do
      @settings.update!(updated_at: 1.hour.from_now)
    end

    assert bundle.reload.pending?
  end
end
