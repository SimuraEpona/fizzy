# Timeline/Roadmap 功能实施指南

## 概述

本文档详细说明如何为 Fizzy 添加 Timeline/Roadmap 视图功能，包括开始日期、截止日期字段，以及基于 Gantt 图的项目规划视图。

## 功能特性

### 核心功能
- 左侧 Backlog 列显示无日期的卡片
- 右侧 Timeline Grid 显示有日期范围的卡片
- Gantt 式横条可视化（完整日期）
- 虚线 + 图标显示（部分日期）
- 开始日期和截止日期字段
- 日期变更事件追踪
- 智能熵系统集成（有日期的卡片不会被自动延迟）
- 响应式设计

### 视图布局
```
┌───────────────────┬─────────────────────────────────────────┐
│   Backlog (3)     │  January  │ February │  March  │  April│
│                   ├─────────────────────────────────────────┤
│ • Card A          │ Card 1  ████████████                    │
│ • Card B  ⭐      │                                         │
│ • Card C          │ Card 2       ██████████████             │
│                   │                                         │
│ [Add dates]       │ Card 3              █████████████       │
│                   │                                         │
│                   │ Card 4    ●──────→ (only start)         │
│                   │                                         │
│                   │ Card 5                  ←──────●        │
│                   │                    (only due date)      │
└───────────────────┴─────────────────────────────────────────┘
```

---

## 实施步骤

### 步骤 1：创建数据库迁移

**文件**: `db/migrate/YYYYMMDDHHMMSS_add_started_on_to_cards.rb`

```ruby
class AddStartedOnToCards < ActiveRecord::Migration[8.0]
  def change
    add_column :cards, :started_on, :date
    add_index :cards, :started_on
    add_index :cards, [:started_on, :due_on]
  end
end
```

**说明**:
- 添加 `started_on` 字段（开始日期）
- `due_on` 字段已存在于 schema（line 206），无需添加
- 添加索引优化查询性能

---

### 步骤 2：创建 Card::Schedulable Concern

**文件**: `app/models/card/schedulable.rb`

```ruby
module Card::Schedulable
  extend ActiveSupport::Concern

  included do
    # 完整日期的卡片
    scope :scheduled, -> { where.not(started_on: nil).where.not(due_on: nil) }

    # 部分日期的卡片
    scope :partially_scheduled, -> {
      where("(started_on IS NOT NULL AND due_on IS NULL) OR (started_on IS NULL AND due_on IS NOT NULL)")
    }

    # 只有开始日期
    scope :only_start_date, -> { where.not(started_on: nil).where(due_on: nil) }

    # 只有截止日期
    scope :only_due_date, -> { where(started_on: nil).where.not(due_on: nil) }

    # 无日期
    scope :unscheduled, -> { where(started_on: nil, due_on: nil) }

    # 按时间线排序（优先使用开始日期，否则使用创建日期）
    scope :timeline_sorted, -> {
      order(Arel.sql("COALESCE(started_on, DATE(created_at)) ASC"))
    }

    # 日期范围查询
    scope :in_date_range, ->(from, to) {
      where("started_on <= ? AND due_on >= ?", to, from)
    }

    # 逾期的卡片（有截止日期且已过期）
    scope :overdue, -> {
      where("due_on < ?", Date.today).open
    }

    # 即将到期的卡片
    scope :due_soon, ->(days = 7) {
      where(due_on: Date.today..days.days.from_now.to_date).open
    }

    # 日期验证
    validates :started_on, comparison: { less_than_or_equal_to: :due_on },
              if: -> { started_on.present? && due_on.present? },
              message: "must be before or equal to due date"
  end

  def scheduled?
    started_on.present? && due_on.present?
  end

  def partially_scheduled?
    (started_on.present? && due_on.nil?) || (started_on.nil? && due_on.present?)
  end

  def unscheduled?
    started_on.nil? && due_on.nil?
  end

  def schedule_status
    if scheduled?
      :scheduled
    elsif started_on.present?
      :only_start_date
    elsif due_on.present?
      :only_due_date
    else
      :unscheduled
    end
  end

  # 用于 Timeline 显示的日期范围
  def timeline_range
    return nil unless scheduled?

    {
      start: started_on,
      end: due_on,
      duration: (due_on - started_on).to_i + 1
    }
  end

  # 推断的日期范围（用于部分日期的卡片）
  def inferred_timeline_range
    if scheduled?
      timeline_range
    elsif started_on.present?
      # 只有开始日期：假设 14 天工期
      { start: started_on, end: started_on + 14.days, inferred: true }
    elsif due_on.present?
      # 只有截止日期：假设 7 天工期
      { start: due_on - 7.days, end: due_on, inferred: true }
    end
  end

  # 检查是否逾期
  def overdue?
    due_on.present? && due_on < Date.today && open?
  end

  # 检查是否即将到期
  def due_soon?(days = 7)
    due_on.present? && due_on.between?(Date.today, days.days.from_now.to_date) && open?
  end
end
```

---

### 步骤 3：更新 Card 模型

**文件**: `app/models/card.rb`

**修改**: 在第 2-4 行的 `include` 列表中添加 `Schedulable`（按字母顺序）

```ruby
# 修改前
include Accessible, Assignable, Attachments, Broadcastable, Closeable, Colored, Entropic, Eventable,
  Exportable, Golden, Mentions, Multistep, Pinnable, Postponable, Promptable,
  Readable, Searchable, Stallable, Statuses, Storage::Tracked, Taggable, Triageable, Watchable

# 修改后
include Accessible, Assignable, Attachments, Broadcastable, Closeable, Colored, Entropic, Eventable,
  Exportable, Golden, Mentions, Multistep, Pinnable, Postponable, Promptable,
  Readable, Schedulable, Searchable, Stallable, Statuses, Storage::Tracked, Taggable, Triageable, Watchable
```

---

### 步骤 4：创建 Board::Timeline 模型

**文件**: `app/models/board/timeline.rb`

```ruby
class Board::Timeline
  attr_reader :board, :filter

  def initialize(board, filter)
    @board = board
    @filter = filter
  end

  # 获取所有卡片（分类）
  def cards_by_status
    base_cards = filter.cards.with_users.preloaded

    {
      scheduled: base_cards.scheduled.timeline_sorted,
      only_start_date: base_cards.only_start_date.order(started_on: :asc),
      only_due_date: base_cards.only_due_date.order(due_on: :asc),
      unscheduled: base_cards.unscheduled.order(created_at: :desc)
    }
  end

  # 仅完整日期的卡片
  def scheduled_cards
    filter.cards.scheduled.with_users.preloaded.timeline_sorted
  end

  # 只有开始日期的卡片
  def only_start_date_cards
    filter.cards.only_start_date.with_users.preloaded.order(started_on: :asc)
  end

  # 只有截止日期的卡片
  def only_due_date_cards
    filter.cards.only_due_date.with_users.preloaded.order(due_on: :asc)
  end

  # 无日期的卡片
  def unscheduled_cards
    filter.cards.unscheduled.with_users.preloaded.order(created_at: :desc)
  end

  # 所有有日期的卡片
  def all_scheduled_cards
    scheduled_cards.to_a + only_start_date_cards.to_a + only_due_date_cards.to_a
  end

  # 日期范围（基于完整日期的卡片）
  def date_range
    scheduled = scheduled_cards.where.not(started_on: nil, due_on: nil)

    return default_date_range if scheduled.empty?

    {
      start: scheduled.minimum(:started_on),
      end: scheduled.maximum(:due_on)
    }
  end

  def default_date_range
    {
      start: Date.today.beginning_of_month,
      end: 3.months.from_now.end_of_month
    }
  end

  # 周列表（用于头部显示）
  def weeks
    range = date_range
    weeks = []
    current = range[:start].beginning_of_week(:monday)

    while current <= range[:end]
      weeks << current
      current += 7.days
    end

    weeks
  end

  # 月列表
  def months
    range = date_range
    months = []
    current = range[:start].beginning_of_month

    while current <= range[:end]
      months << current
      current = current.next_month
    end

    months
  end

  # 计算某个月有多少周
  def weeks_in_month(month)
    month_weeks = weeks.select { |week| week.month == month.month && week.year == month.year }
    month_weeks.count
  end

  # 计算卡片在网格中的位置
  def card_grid_position(card)
    return nil unless card.scheduled?

    start_week = weeks.index { |week| week <= card.started_on && card.started_on < week + 7.days }
    end_week = weeks.index { |week| week <= card.due_on && card.due_on < week + 7.days }

    return nil if start_week.nil? || end_week.nil?

    {
      start_col: start_week + 1,  # CSS grid is 1-indexed
      span: end_week - start_week + 1,
      style: "grid-column: #{start_week + 1} / span #{end_week - start_week + 1}; --card-color: #{card.color};"
    }
  end

  # 部分日期卡片的位置计算
  def partial_card_position(card, type)
    total_weeks = weeks.count

    if type == :start && card.started_on
      # 从开始日期显示到 timeline 结束（虚线）
      start_week = weeks.index { |week| week <= card.started_on && card.started_on < week + 7.days }
      return nil if start_week.nil?

      span = total_weeks - start_week

      {
        style: "grid-column: #{start_week + 1} / span #{span}; --card-color: #{card.color};"
      }
    elsif type == :due && card.due_on
      # 从 timeline 开始到截止日期（虚线）
      due_week = weeks.index { |week| week <= card.due_on && card.due_on < week + 7.days }
      return nil if due_week.nil?

      {
        style: "grid-column: 1 / #{due_week + 2}; --card-color: #{card.color};"
      }
    end
  end
end
```

**修复说明**:
- `week + 1.week` 改为 `week + 7.days`（避免 Date 与 ActiveSupport::Duration 运算问题）
- `current += 1.month` 改为 `current = current.next_month`
- `card.color.value` 改为 `card.color`（Card 的 color 方法直接返回颜色值）

---

### 步骤 5：创建 Boards::TimelinesController

**文件**: `app/controllers/boards/timelines_controller.rb`

```ruby
class Boards::TimelinesController < ApplicationController
  include BoardScoped
  include FilterScoped

  def show
    @timeline = Board::Timeline.new(@board, @filter)
  end
end
```

**注意**: `BoardScoped` 应该在 `FilterScoped` 之前，因为 filter 可能依赖 board。

---

### 步骤 6：添加路由

**文件**: `config/routes.rb`

**修改**: 在 `resources :boards` 块中的 `resource :entropy` 之后添加 timeline 路由

```ruby
resources :boards do
  scope module: :boards do
    resource :subscriptions
    resource :involvement
    resource :publication
    resource :entropy
    resource :timeline  # 添加这一行

    namespace :columns do
      resource :not_now
      resource :stream
      resource :closed
    end

    resources :columns
  end

  resources :cards, only: :create

  resources :webhooks do
    scope module: :webhooks do
      resource :activation, only: :create
    end
  end
end
```

**注意**: 使用 `resource :timeline` 而非 `resource :timeline, only: :show`，遵循项目中其他类似路由的风格。

---

### 步骤 7：创建 Timeline 视图

#### 主视图文件

**文件**: `app/views/boards/timelines/show.html.erb`

```erb
<% @page_title = "#{@board.name} - Timeline" %>
<% @body_class = "contained-scrolling" %>

<% content_for :header do %>
  <div class="header__actions header__actions--start">
    <%= link_to @board.name, @board, class: "btn btn--back" %>
  </div>

  <h1 class="header__title">Timeline</h1>

  <div class="header__actions header__actions--end hide-on-native">
  </div>
<% end %>

<div class="timeline-container">

  <!-- 左侧：Backlog 列 -->
  <aside class="timeline__backlog">
    <div class="timeline__backlog-header">
      <h3 class="timeline__backlog-title">
        Backlog
        <span class="timeline__backlog-count"><%= @timeline.unscheduled_cards.count %></span>
      </h3>
      <p class="timeline__backlog-hint">Cards without dates</p>
    </div>

    <div class="timeline__backlog-cards">
      <% @timeline.unscheduled_cards.each do |card| %>
        <%= render "boards/timelines/backlog_card", card: card %>
      <% end %>

      <% if @timeline.unscheduled_cards.empty? %>
        <div class="timeline__backlog-empty">
          <p>All cards scheduled</p>
        </div>
      <% end %>
    </div>
  </aside>

  <!-- 右侧：Timeline 主区域 -->
  <main class="timeline__main">

    <!-- 日期头部 -->
    <div class="timeline__header" style="--total-weeks: <%= @timeline.weeks.count %>">
      <div class="timeline__months">
        <% @timeline.months.each do |month| %>
          <div class="timeline__month-header"
               style="grid-column: span <%= @timeline.weeks_in_month(month) %>">
            <%= month.strftime("%B %Y") %>
          </div>
        <% end %>
      </div>

      <div class="timeline__weeks">
        <% @timeline.weeks.each do |week| %>
          <div class="timeline__week-header">
            <%= week.strftime("%b %d") %>
          </div>
        <% end %>
      </div>
    </div>

    <!-- 时间轴 Grid -->
    <div class="timeline__grid" style="--total-weeks: <%= @timeline.weeks.count %>">

      <!-- 完整日期的卡片 -->
      <% @timeline.scheduled_cards.each do |card| %>
        <%= render "boards/timelines/scheduled_card", card: card, timeline: @timeline %>
      <% end %>

      <!-- 只有开始日期的卡片 -->
      <% @timeline.only_start_date_cards.each do |card| %>
        <%= render "boards/timelines/partial_card", card: card, timeline: @timeline, type: :start %>
      <% end %>

      <!-- 只有截止日期的卡片 -->
      <% @timeline.only_due_date_cards.each do |card| %>
        <%= render "boards/timelines/partial_card", card: card, timeline: @timeline, type: :due %>
      <% end %>

      <% if @timeline.all_scheduled_cards.empty? %>
        <div class="timeline__empty-state">
          <p>No scheduled cards yet</p>
          <p class="timeline__empty-hint">
            Add dates to cards to see them on the timeline
          </p>
        </div>
      <% end %>
    </div>
  </main>
</div>
```

#### Backlog 卡片 Partial

**文件**: `app/views/boards/timelines/_backlog_card.html.erb`

```erb
<div class="backlog-card" data-card-id="<%= card.id %>">

  <div class="backlog-card__header">
    <%= link_to card.title, card_path(card), class: "backlog-card__title" %>

    <% if card.golden? %>
      <span class="backlog-card__badge backlog-card__badge--golden"></span>
    <% end %>
  </div>

  <% if card.assignees.any? %>
    <div class="backlog-card__assignees">
      <% card.assignees.first(3).each do |assignee| %>
        <%= avatar_tag assignee, size: :small %>
      <% end %>
    </div>
  <% end %>

  <div class="backlog-card__footer">
    <span class="backlog-card__meta">
      <% if card.assignees.any? %>
        <%= icon_tag "person-add" %>
        <%= card.assignees.count if card.assignees.count > 1 %>
      <% end %>
    </span>

    <%= link_to "Add dates", card_path(card), class: "backlog-card__action" %>
  </div>
</div>
```

**修复说明**:
- `icon_tag "person"` 改为 `icon_tag "person-add"`（项目中存在的图标）
- 使用 `avatar_tag` helper（项目中已有）
- 移除 `turbo_frame: "modal"`（需要确认项目是否使用 modal frame）

#### 完整日期卡片 Partial

**文件**: `app/views/boards/timelines/_scheduled_card.html.erb`

```erb
<% position = timeline.card_grid_position(card) %>
<% return unless position %>

<div class="timeline__card"
     data-card-id="<%= card.id %>"
     style="<%= position[:style] %>">

  <div class="timeline__card-content">
    <%= link_to card.title, card_path(card), class: "timeline__card-link" %>

    <div class="timeline__card-meta">
      <% if card.assignees.any? %>
        <div class="timeline__card-assignees">
          <% card.assignees.first(2).each do |assignee| %>
            <%= avatar_tag assignee, size: :tiny %>
          <% end %>
        </div>
      <% end %>

      <div class="timeline__card-dates">
        <%= card.started_on.strftime("%b %d") %> - <%= card.due_on.strftime("%b %d") %>
        <span class="timeline__card-duration">
          (<%= (card.due_on - card.started_on).to_i + 1 %>d)
        </span>
      </div>
    </div>
  </div>
</div>
```

#### 部分日期卡片 Partial

**文件**: `app/views/boards/timelines/_partial_card.html.erb`

```erb
<% position = timeline.partial_card_position(card, type) %>
<% return unless position %>

<div class="timeline__card timeline__card--partial timeline__card--<%= type %>"
     data-card-id="<%= card.id %>"
     style="<%= position[:style] %>">

  <% if type == :start %>
    <!-- 只有开始日期：显示左边的起点 + 虚线 -->
    <div class="timeline__card-marker timeline__card-marker--start">
      <%= icon_tag "arrow-right" %>
    </div>
    <div class="timeline__card-content timeline__card-content--dashed">
      <%= link_to card.title, card_path(card), class: "timeline__card-link" %>
      <span class="timeline__card-hint">No end date</span>
    </div>
  <% else %>
    <!-- 只有截止日期：显示虚线 + 右边的终点 -->
    <div class="timeline__card-content timeline__card-content--dashed">
      <%= link_to card.title, card_path(card), class: "timeline__card-link" %>
      <span class="timeline__card-hint">No start date</span>
    </div>
    <div class="timeline__card-marker timeline__card-marker--due">
      <%= icon_tag "checkmark" %>
    </div>
  <% end %>
</div>
```

**修复说明**:
- 使用 `icon_tag` 而非 emoji（保持与项目风格一致）

---

### 步骤 8：创建 Timeline CSS 样式

**文件**: `app/assets/stylesheets/timeline.css`

```css
@layer components {
  /* Timeline Container */
  .timeline-container {
    display: grid;
    grid-template-columns: 280px 1fr;
    gap: var(--inline-space-double);
    height: calc(100vh - 120px);
    overflow: hidden;
    padding: var(--main-padding);
  }

  /* ====== Left Backlog Column ====== */
  .timeline__backlog {
    background: var(--color-canvas);
    border-right: var(--border);
    border-radius: 0.5rem;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .timeline__backlog-header {
    padding: var(--block-space);
    border-bottom: var(--border);
    background: var(--color-ink-lightest);
  }

  .timeline__backlog-title {
    display: flex;
    align-items: center;
    gap: var(--inline-space-half);
    font-size: var(--text-medium);
    font-weight: 600;
    margin: 0 0 var(--block-space-half) 0;
  }

  .timeline__backlog-count {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 1.5rem;
    height: 1.5rem;
    padding: 0 var(--inline-space-half);
    background: var(--color-link);
    color: var(--color-white);
    border-radius: 0.75rem;
    font-size: var(--text-x-small);
    font-weight: 600;
  }

  .timeline__backlog-hint {
    font-size: var(--text-x-small);
    color: var(--color-ink-medium);
    margin: 0;
    line-height: 1.4;
  }

  .timeline__backlog-cards {
    flex: 1;
    overflow-y: auto;
    padding: var(--block-space-half);
    display: flex;
    flex-direction: column;
    gap: var(--block-space-half);
  }

  .timeline__backlog-empty {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    text-align: center;
    padding: var(--block-space-double);
    color: var(--color-positive);
    font-weight: 500;
  }

  /* Backlog Card Styles */
  .backlog-card {
    background: var(--color-canvas);
    border: var(--border);
    border-radius: 0.5rem;
    padding: var(--block-space);
    transition: all 0.2s ease;
  }

  .backlog-card:hover {
    border-color: var(--color-link);
    box-shadow: var(--shadow);
  }

  .backlog-card__header {
    display: flex;
    justify-content: space-between;
    align-items: start;
    margin-bottom: var(--block-space-half);
    gap: var(--inline-space-half);
  }

  .backlog-card__title {
    color: var(--color-ink);
    text-decoration: none;
    font-weight: 500;
    font-size: var(--text-small);
    line-height: 1.4;
    flex: 1;
    overflow: hidden;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
  }

  .backlog-card__title:hover {
    color: var(--color-link);
    text-decoration: underline;
  }

  .backlog-card__badge--golden {
    width: 1rem;
    height: 1rem;
    background: var(--color-golden);
    border-radius: 50%;
    flex-shrink: 0;
  }

  .backlog-card__assignees {
    display: flex;
    gap: 0.25rem;
    margin-bottom: var(--block-space-half);
  }

  .backlog-card__footer {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-top: var(--block-space-half);
    padding-top: var(--block-space-half);
    border-top: var(--border);
  }

  .backlog-card__meta {
    display: flex;
    align-items: center;
    gap: 0.25rem;
    font-size: var(--text-x-small);
    color: var(--color-ink-medium);
  }

  .backlog-card__action {
    padding: 0.25rem 0.5rem;
    font-size: var(--text-x-small);
    color: var(--color-link);
    text-decoration: none;
    border-radius: 0.25rem;
    transition: all 0.2s ease;
    font-weight: 500;
  }

  .backlog-card__action:hover {
    background: var(--color-selected-light);
  }

  /* ====== Right Timeline Main Area ====== */
  .timeline__main {
    display: flex;
    flex-direction: column;
    overflow: hidden;
    background: var(--color-canvas);
    border: var(--border);
    border-radius: 0.5rem;
  }

  .timeline__header {
    padding: var(--block-space);
    background: var(--color-ink-lightest);
    border-bottom: var(--border);
    position: sticky;
    top: 0;
    z-index: var(--z-events-column-header);
  }

  .timeline__months,
  .timeline__weeks {
    display: grid;
    grid-template-columns: repeat(var(--total-weeks), minmax(80px, 1fr));
    gap: 1px;
  }

  .timeline__month-header {
    padding: var(--block-space-half);
    text-align: center;
    font-weight: 600;
    font-size: var(--text-normal);
    background: var(--color-selected-light);
    color: var(--color-link);
    border-radius: 0.25rem;
    margin-bottom: var(--block-space-half);
  }

  .timeline__week-header {
    padding: var(--block-space-half);
    text-align: center;
    font-size: var(--text-x-small);
    color: var(--color-ink-medium);
    font-weight: 500;
  }

  .timeline__grid {
    flex: 1;
    overflow: auto;
    padding: var(--block-space);
    display: grid;
    grid-template-columns: repeat(var(--total-weeks), minmax(80px, 1fr));
    gap: var(--block-space-half) 0;
    align-content: start;
  }

  /* ====== Timeline Card Styles ====== */
  .timeline__card {
    display: flex;
    align-items: center;
    min-height: 3rem;
    padding: var(--block-space-half);
    background-color: color-mix(in srgb, var(--card-color) 30%, transparent);
    border: 2px solid var(--card-color);
    border-radius: 0.5rem;
    cursor: pointer;
    transition: all 0.2s ease;
    overflow: hidden;
  }

  .timeline__card:hover {
    background-color: color-mix(in srgb, var(--card-color) 50%, transparent);
    box-shadow: var(--shadow);
    transform: translateY(-2px);
    z-index: 5;
  }

  /* Partial Cards (only start or only due date) */
  .timeline__card--partial {
    background-color: transparent;
    border: 2px dashed var(--card-color);
    opacity: 0.7;
  }

  .timeline__card--partial:hover {
    opacity: 1;
    background-color: color-mix(in srgb, var(--card-color) 10%, transparent);
  }

  .timeline__card-marker {
    font-size: var(--text-normal);
    flex-shrink: 0;
    margin: 0 var(--inline-space-half);
    color: var(--card-color);
  }

  .timeline__card-content {
    flex: 1;
    overflow: hidden;
    min-width: 0;
  }

  .timeline__card-content--dashed {
    position: relative;
  }

  .timeline__card-content--dashed::before {
    content: '';
    position: absolute;
    top: 50%;
    left: 0;
    right: 0;
    height: 2px;
    background: repeating-linear-gradient(
      to right,
      var(--card-color) 0,
      var(--card-color) 4px,
      transparent 4px,
      transparent 8px
    );
    opacity: 0.5;
    z-index: -1;
  }

  .timeline__card-link {
    color: var(--color-ink);
    text-decoration: none;
    font-weight: 500;
    font-size: var(--text-small);
    display: block;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .timeline__card-link:hover {
    text-decoration: underline;
  }

  .timeline__card-hint {
    display: block;
    font-size: var(--text-xx-small);
    color: var(--color-negative);
    font-style: italic;
    margin-top: 2px;
  }

  .timeline__card-meta {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-top: var(--block-space-half);
    gap: var(--inline-space-half);
  }

  .timeline__card-assignees {
    display: flex;
    gap: 2px;
  }

  .timeline__card-dates {
    font-size: var(--text-xx-small);
    color: var(--color-ink-medium);
    white-space: nowrap;
  }

  .timeline__card-duration {
    font-weight: 600;
  }

  /* Empty State */
  .timeline__empty-state {
    grid-column: 1 / -1;
    text-align: center;
    padding: var(--block-space-double);
    color: var(--color-ink-medium);
  }

  .timeline__empty-hint {
    margin-top: var(--block-space-half);
    font-size: var(--text-small);
  }

  /* ====== Responsive Design ====== */
  @media (max-width: 1024px) {
    .timeline-container {
      grid-template-columns: 240px 1fr;
    }
  }

  @media (max-width: 768px) {
    .timeline-container {
      grid-template-columns: 1fr;
      grid-template-rows: auto 1fr;
    }

    .timeline__backlog {
      border-right: none;
      border-bottom: var(--border);
      max-height: 30vh;
    }

    .timeline__header {
      overflow-x: auto;
    }

    .timeline__grid {
      min-width: 600px;
    }
  }
}
```

**修复说明**: 使用 Fizzy 实际的 CSS 变量：
- `--space-*` → `--inline-space`, `--block-space`
- `--color-surface` → `--color-canvas`, `--color-ink-lightest`
- `--color-border` → `--border`（这是完整的 border 声明）
- `--radius-*` → 直接使用 `0.5rem` 等
- `--font-size-*` → `--text-small`, `--text-x-small` 等
- `--color-text-secondary` → `--color-ink-medium`
- `--color-accent` → `--color-link`
- 添加 `@layer components` 包裹

---

### 步骤 9：更新卡片编辑表单

**文件**: `app/views/cards/edit.html.erb`

**修改**: 在 `form.rich_textarea :description` 之后添加日期字段

```erb
<%= turbo_frame_tag @card, :edit do %>
  <%# When entering edit mode, this turbo-stream updates the button area to show
      "Save changes" instead of "Edit". Turbo processes this stream as part of the
      frame response. %>
  <%= turbo_stream.update dom_id(@card, :card_closure_toggle) do %>
    <%= render "cards/container/save_button", card: @card %>
  <% end %>

  <%= form_with model: @card, id: dom_id(@card, :edit_form),
        data: { controller: "autoresize form local-save", local_save_key_value: "card-#{@card.id}", action: "turbo:submit-end->local-save#submit" } do |form| %>
    <h1 class="card__title flex align-start gap-half">
      <%= form.label :title, class: "flex flex-column align-center autoresize__wrapper", data: { autoresize_target: "wrapper", autoresize_clone_value: "" } do %>
        <%= form.text_area :title, class: "card-field__title autoresize__textarea input input--textarea full-width borderless txt-align-start hide-focus-ring hide-scrollbar",
              required: true, autofocus: true, placeholder: "Name it…", rows: 1, dir: "auto", maxlength: 255,
              data: { autoresize_target: "textarea", action: "input->autoresize#resize keydown.enter->form#submit:prevent keydown.ctrl+enter->form#submit:prevent keydown.meta+enter->form#submit:prevent keydown.esc->form#cancel focus->form#select" } %>
      <% end %>
    </h1>

    <%= form.rich_textarea :description, class: "card__description rich-text-content",
          placeholder: "Add some notes, context, pictures, or video about this…",
          data: { local_save_target: "input", action: "lexxy:change->local-save#save turbo:morph-element->local-save#restoreContent keydown.ctrl+enter->form#submit:prevent keydown.meta+enter->form#submit:prevent keydown.esc->form#cancel:stop" } do %>
      <%= general_prompts(@card.board) %>
    <% end %>

    <!-- 日期字段 -->
    <div class="card__dates flex gap">
      <div class="card__date-field flex flex-column gap-half">
        <%= form.label :started_on, "Start date", class: "txt-small txt-ink-medium" %>
        <%= form.date_field :started_on, class: "input",
              data: { local_save_target: "input", action: "change->local-save#save" } %>
      </div>

      <div class="card__date-field flex flex-column gap-half">
        <%= form.label :due_on, "Due date", class: "txt-small txt-ink-medium" %>
        <%= form.date_field :due_on, class: "input",
              data: { local_save_target: "input", action: "change->local-save#save" } %>
      </div>
    </div>

    <%= link_to "Close editor and discard changes", @card,
          data: { form_target: "cancel", bridge__form_target: "cancel", bridge_title: "Cancel" }, hidden: true %>
  <% end %>
<% end %>
```

**新增**: 在 `app/assets/stylesheets/cards.css` 中添加日期字段样式：

```css
/* 添加到 cards.css 文件末尾 */
.card__dates {
  margin-top: var(--block-space);
  padding-top: var(--block-space);
  border-top: var(--border);
}

.card__date-field {
  flex: 1;
}

.card__date-field input[type="date"] {
  width: 100%;
}
```

---

### 步骤 10：更新 CardsController

**文件**: `app/controllers/cards_controller.rb`

**修改**: 在 `card_params` 方法中添加新参数

```ruby
# 修改前（第 68-70 行）
def card_params
  params.expect(card: [ :title, :description, :image, :created_at, :last_active_at ])
end

# 修改后
def card_params
  params.expect(card: [ :title, :description, :image, :created_at, :last_active_at, :started_on, :due_on ])
end
```

---

### 步骤 11：添加日期变更事件追踪

**文件**: `app/models/card/eventable.rb`

**修改 1**: 在 `included do` 块中添加新的回调（第 6-9 行之后）

```ruby
included do
  before_create { self.last_active_at ||= created_at || Time.current }

  after_save :track_title_change, if: :saved_change_to_title?
  after_save :track_started_on_change, if: :saved_change_to_started_on?
  after_save :track_due_on_change, if: :saved_change_to_due_on?
end
```

**修改 2**: 在 `private` 部分添加新方法（第 33 行之后）

```ruby
def track_started_on_change
  track_event "started_date_changed", particulars: {
    old_started_on: started_on_before_last_save&.iso8601,
    new_started_on: started_on&.iso8601
  }
end

def track_due_on_change
  track_event "due_date_changed", particulars: {
    old_due_on: due_on_before_last_save&.iso8601,
    new_due_on: due_on&.iso8601
  }
end
```

---

### 步骤 12：更新 Event::Description

**文件**: `app/models/event/description.rb`

**修改**: 在 `action_sentence` 方法的 `case` 语句中添加日期变更的描述（第 80-82 行之后）

```ruby
def action_sentence(creator, card_title)
  case event.action
  when "card_assigned"
    assigned_sentence(creator, card_title)
  when "card_unassigned"
    unassigned_sentence(creator, card_title)
  # ... 其他 when 子句 ...
  when "card_sent_back_to_triage"
    %(#{creator} moved #{card_title} back to "Maybe?")
  # 添加以下两行
  when "card_started_date_changed"
    started_date_changed_sentence(creator, card_title)
  when "card_due_date_changed"
    due_date_changed_sentence(creator, card_title)
  end
end
```

**添加**: 在 `private` 部分添加新的描述方法

```ruby
def started_date_changed_sentence(creator, card_title)
  new_date = event.particulars.dig("particulars", "new_started_on")
  old_date = event.particulars.dig("particulars", "old_started_on")

  if new_date.present? && old_date.present?
    "#{creator} changed start date of #{card_title}"
  elsif new_date.present?
    "#{creator} set start date for #{card_title}"
  else
    "#{creator} removed start date from #{card_title}"
  end
end

def due_date_changed_sentence(creator, card_title)
  new_date = event.particulars.dig("particulars", "new_due_on")
  old_date = event.particulars.dig("particulars", "old_due_on")

  if new_date.present? && old_date.present?
    "#{creator} changed due date of #{card_title}"
  elsif new_date.present?
    "#{creator} set due date for #{card_title}"
  else
    "#{creator} removed due date from #{card_title}"
  end
end
```

---

### 步骤 13：（可选）更新 TIMELINEABLE_ACTIONS

如果希望日期变更在 Activity Timeline 中显示，需要更新：

**文件**: `app/models/user/day_timeline.rb`

**修改**: 在 `TIMELINEABLE_ACTIONS` 数组中添加新 action（第 49-62 行）

```ruby
TIMELINEABLE_ACTIONS = %w[
  card_assigned
  card_unassigned
  card_published
  card_closed
  card_reopened
  card_collection_changed
  card_board_changed
  card_postponed
  card_auto_postponed
  card_triaged
  card_sent_back_to_triage
  card_started_date_changed
  card_due_date_changed
  comment_created
]
```

---

### 步骤 14：修改熵系统

**文件**: `app/models/card/entropic.rb`

**修改**: 在 `due_to_be_postponed` scope 中添加日期检查（第 5-11 行）

```ruby
scope :due_to_be_postponed, -> do
  active
    .joins(board: :account)
    .left_outer_joins(board: :entropy)
    .joins("LEFT OUTER JOIN entropies AS account_entropies ON account_entropies.account_id = accounts.id AND account_entropies.container_type = 'Account' AND account_entropies.container_id = accounts.id")
    .where("last_active_at <= #{connection.date_subtract('?', 'COALESCE(entropies.auto_postpone_period, account_entropies.auto_postpone_period)')}", Time.now)
    .where("due_on IS NULL OR due_on < ?", Date.today)  # 添加这一行：排除有未来截止日期的卡片
end
```

**说明**: 这确保有截止日期且未逾期的卡片不会被自动延迟。

---

### 步骤 15：在 Board 视图添加 Timeline 按钮

**文件**: `app/views/boards/show.html.erb`

**修改**: 在头部添加 Timeline 按钮（第 16-18 行）

```erb
<div class="header__actions header__actions--end hide-on-native">
  <%= link_to "Timeline", board_timeline_path(@board), class: "btn" %>
  <%= link_to_edit_board @board %>
</div>
```

---

### 步骤 16：在卡片详情页显示日期信息

**文件**: `app/views/cards/display/common/_meta.html.erb`

**修改**: 在现有元信息之后添加日期显示（第 24 行之后）

```erb
<% if card.started_on.present? || card.due_on.present? %>
  <span class="card__meta-text card__meta-text--dates overflow-ellipsis">
    <%= icon_tag "calendar" %>
    <% if card.scheduled? %>
      <%= card.started_on.strftime("%b %d") %> - <%= card.due_on.strftime("%b %d, %Y") %>
    <% elsif card.started_on.present? %>
      Starts <%= card.started_on.strftime("%b %d, %Y") %>
    <% elsif card.due_on.present? %>
      Due <%= card.due_on.strftime("%b %d, %Y") %>
    <% end %>
  </span>
<% end %>
```

**注意**: 需要确认 `calendar` 图标是否存在，如果不存在可以使用 `refresh--meta` 或其他已有图标。

---

## 测试文件

### 步骤 17：添加测试

#### Model 测试

**文件**: `test/models/card/schedulable_test.rb`

```ruby
require "test_helper"

class Card::SchedulableTest < ActiveSupport::TestCase
  setup do
    @card = cards(:one)
  end

  test "scheduled? returns true when both dates are present" do
    @card.update!(started_on: Date.today, due_on: Date.today + 7.days)
    assert @card.scheduled?
  end

  test "scheduled? returns false when only start date is present" do
    @card.update!(started_on: Date.today, due_on: nil)
    assert_not @card.scheduled?
  end

  test "unscheduled? returns true when no dates are present" do
    @card.update!(started_on: nil, due_on: nil)
    assert @card.unscheduled?
  end

  test "validates start date is before due date" do
    @card.started_on = Date.today + 7.days
    @card.due_on = Date.today
    assert_not @card.valid?
    assert_includes @card.errors[:started_on], "must be before or equal to due date"
  end

  test "scheduled scope returns cards with both dates" do
    @card.update!(started_on: Date.today, due_on: Date.today + 7.days)
    assert_includes Card.scheduled, @card
  end

  test "unscheduled scope returns cards without dates" do
    @card.update!(started_on: nil, due_on: nil)
    assert_includes Card.unscheduled, @card
  end

  test "overdue? returns true when due date is past" do
    @card.update!(due_on: Date.yesterday)
    assert @card.overdue?
  end
end
```

#### Controller 测试

**文件**: `test/controllers/boards/timelines_controller_test.rb`

```ruby
require "test_helper"

class Boards::TimelinesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:david)
    @board = boards(:one)
    sign_in_as @user
  end

  test "should get show" do
    get board_timeline_url(@board)
    assert_response :success
  end

  test "should display unscheduled cards in backlog" do
    card = @board.cards.create!(title: "Unscheduled", creator: @user, status: "published")
    get board_timeline_url(@board)
    assert_select ".backlog-card", text: /Unscheduled/
  end

  test "should display scheduled cards in timeline" do
    card = @board.cards.create!(
      title: "Scheduled",
      creator: @user,
      status: "published",
      started_on: Date.today,
      due_on: Date.today + 7.days
    )
    get board_timeline_url(@board)
    assert_select ".timeline__card", text: /Scheduled/
  end
end
```

---

## 执行步骤

### 1. 创建所有新文件
```
db/migrate/YYYYMMDDHHMMSS_add_started_on_to_cards.rb
app/models/card/schedulable.rb
app/models/board/timeline.rb
app/controllers/boards/timelines_controller.rb
app/views/boards/timelines/show.html.erb
app/views/boards/timelines/_backlog_card.html.erb
app/views/boards/timelines/_scheduled_card.html.erb
app/views/boards/timelines/_partial_card.html.erb
app/assets/stylesheets/timeline.css
test/models/card/schedulable_test.rb
test/controllers/boards/timelines_controller_test.rb
```

### 2. 修改现有文件
```
app/models/card.rb                           # 添加 Schedulable concern
app/models/card/eventable.rb                 # 添加日期变更事件追踪
app/models/card/entropic.rb                  # 排除有日期的卡片
app/models/event/description.rb              # 添加日期变更描述
app/models/user/day_timeline.rb              # （可选）添加到 TIMELINEABLE_ACTIONS
app/controllers/cards_controller.rb          # 添加 card_params
app/views/cards/edit.html.erb                # 添加日期字段
app/views/cards/display/common/_meta.html.erb # 显示日期信息
app/views/boards/show.html.erb               # 添加 Timeline 按钮
app/assets/stylesheets/cards.css             # 添加日期字段样式
config/routes.rb                             # 添加 timeline 路由
```

### 3. 运行迁移
```bash
bin/rails db:migrate
```

### 4. 运行测试
```bash
bin/rails test test/models/card/schedulable_test.rb
bin/rails test test/controllers/boards/timelines_controller_test.rb
```

### 5. 启动服务器测试
```bash
bin/dev
```

### 6. 手动测试
1. 访问任意 Board
2. 点击头部的 "Timeline" 按钮
3. 编辑卡片，添加开始日期和截止日期
4. 查看 Timeline 视图中的卡片展示
5. 验证日期变更事件是否正确记录

---

## 文件清单

### 新建文件（11个）
| 文件 | 说明 |
|------|------|
| `db/migrate/xxx_add_started_on_to_cards.rb` | 数据库迁移 |
| `app/models/card/schedulable.rb` | 日期相关 concern |
| `app/models/board/timeline.rb` | Timeline 业务逻辑 |
| `app/controllers/boards/timelines_controller.rb` | 控制器 |
| `app/views/boards/timelines/show.html.erb` | 主视图 |
| `app/views/boards/timelines/_backlog_card.html.erb` | Backlog 卡片 |
| `app/views/boards/timelines/_scheduled_card.html.erb` | 完整日期卡片 |
| `app/views/boards/timelines/_partial_card.html.erb` | 部分日期卡片 |
| `app/assets/stylesheets/timeline.css` | 样式文件 |
| `test/models/card/schedulable_test.rb` | Model 测试 |
| `test/controllers/boards/timelines_controller_test.rb` | Controller 测试 |

### 修改文件（11个）
| 文件 | 修改内容 |
|------|----------|
| `app/models/card.rb` | 添加 `Schedulable` concern |
| `app/models/card/eventable.rb` | 添加日期变更事件追踪 |
| `app/models/card/entropic.rb` | 排除有日期的卡片 |
| `app/models/event/description.rb` | 添加日期变更描述 |
| `app/models/user/day_timeline.rb` | 添加到 TIMELINEABLE_ACTIONS（可选） |
| `app/controllers/cards_controller.rb` | 添加 `started_on`, `due_on` 到 params |
| `app/views/cards/edit.html.erb` | 添加日期输入字段 |
| `app/views/cards/display/common/_meta.html.erb` | 显示日期信息 |
| `app/views/boards/show.html.erb` | 添加 Timeline 按钮 |
| `app/assets/stylesheets/cards.css` | 添加日期字段样式 |
| `config/routes.rb` | 添加 timeline 路由 |

---

## 后续增强建议

### 可选功能
- 拖拽功能（拖动横条改变日期）
- 缩放功能（周/月/季度视图切换）
- 依赖关系可视化（箭头连接）
- 里程碑标记（垂直线）
- 资源分配视图（按 assignee 分组）
- 优先级字段（P1/P2/P3）
- 导出为图片/PDF

---

## 注意事项

1. **CSS 变量**: 样式使用 Fizzy 实际的 CSS 变量（`--inline-space`, `--block-space`, `--color-ink-*` 等）
2. **多租户**: 功能自动支持多租户，通过 `Current.account`
3. **权限**: Timeline 视图继承 Board 的访问权限（通过 `BoardScoped`）
4. **事件系统**: 日期变更会触发 webhook 和通知
5. **熵系统**: 有未来截止日期的卡片不会被自动延迟

---

## 遇到问题？

### 常见问题

**Q: Timeline 视图空白？**
A: 检查是否运行了迁移，确保 `started_on` 字段存在。

**Q: 日期字段不保存？**
A: 确认 `CardsController` 的 `card_params` 包含了 `:started_on` 和 `:due_on`。

**Q: CSS 样式不生效？**
A: 确认 `timeline.css` 文件在 `app/assets/stylesheets/` 目录下，Propshaft 会自动加载。

**Q: 卡片不显示在 Timeline 上？**
A: 检查卡片是否有 `started_on` 和 `due_on` 值。无日期的卡片会显示在 Backlog 中。

**Q: 日期变更事件不显示？**
A: 检查 `Event::Description` 中是否添加了对应的描述方法。

---

## 完成！

按照以上步骤操作，你就能完整实现 Timeline/Roadmap 功能。所有代码都遵循 Fizzy 的编码标准和架构模式。
