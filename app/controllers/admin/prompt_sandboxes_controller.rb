class Admin::PromptSandboxesController < AdminController
  include DayTimelinesScoped

  def show
    @llm_model = params[:llm_model] || Event::Summarizer::LLM_MODEL

    if @prompt = cookies[:prompt].presence
      @weekly_summary = build_weekly_summary
      cookies.delete :prompt
    else
      @weekly_summary = @day_timeline.weekly_summary
      @prompt = Event::Summarizer::PROMPT
    end
  end

  def create
    @prompt = params[:prompt]
    @llm_model = params[:llm_model]
    cookies[:prompt] = @prompt
    redirect_to admin_prompt_sandbox_path(day: @day_timeline.day, llm_model: @llm_model)
  end

  private
    def build_weekly_summary
      period = PeriodSummary::Period.new(Current.user.collections, starts_at: @day_timeline.day.beginning_of_week(:sunday), duration: 1.week)
      summarizer = Event::Summarizer.new(period.events, prompt: @prompt, llm_model: @llm_model)
      content = summarizer.summarized_content
      PeriodSummary.new(content: content, cost_in_microcents: summarizer.cost.in_microcents)
    end
end
