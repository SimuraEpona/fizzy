module NotificationsHelper
  def event_notification_title(event)
    if event.commented?
      "RE: " + event.card.title
    elsif event.assigned?
      "Assigned to you: " + event.card.title
    else
      event.card.title
    end
  end

  def event_notification_body(event)
    name = event.creator.name

    if event.closed?
      "Closed by #{name}"
    elsif event.published?
      "Added by #{name}"
    elsif event.commented?
      "#{strip_tags(event.comment.body_html).blank? ? "#{name} replied" : "#{event.creator.name}:" } #{strip_tags(event.comment.body_html).truncate(200)}"
    else
      name
    end
  end

  def notification_tag(notification, &)
    tag.div id: dom_id(notification), class: "notification tray__item border-radius txt-normal" do
      # TODO: Temporary, I'll remove this. Right now, we support linking comments, but we should be linking messages.
      resource = notification.resource.is_a?(Message) ? notification.resource.comment : notification.resource
      concat(
        link_to(resource,
          class: "notification__content border-radius shadow fill-white flex align-start txt-align-start gap flex-item-grow max-width border txt-ink",
          data: { action: "click->dialog#close", turbo_frame: "_top" },
          &)
      )
      concat(notification_mark_read_button(notification))
    end
  end

  def notification_mark_read_button(notification)
    button_to read_notification_path(notification),
      class: "notification__unread_indicator btn borderless",
      title: "Mark as read",
      data: { turbo_frame: "_top" } do
      concat(image_tag("remove-med.svg", class: "unread_icon", size: 12, aria: { hidden: true }))
      concat(tag.span("Mark as read", class: "for-screen-reader"))
    end
  end

  def notifications_next_page_link(page)
    unless @page.last?
      tag.div id: "next_page", data: { controller: "fetch-on-visible", fetch_on_visible_url_value: notifications_path(page: @page.next_param) }
    end
  end
end
