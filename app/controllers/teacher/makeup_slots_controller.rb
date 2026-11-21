module Teacher
  # T-06 振替枠の一覧、T-07 振替枠の登録・編集（先生）
  class MakeupSlotsController < ApplicationController
    def index
      authorize MakeupSlot
      @makeup_slots = policy_scope(MakeupSlot).upcoming
    end

    def new
      authorize MakeupSlot
      @makeup_slot = MakeupSlot.new(capacity: 1)
    end

    def create
      authorize MakeupSlot
      @makeup_slot = MakeupSlot.new(slot_params)

      if save(@makeup_slot)
        redirect_to teacher_makeup_slots_path, notice: "振替枠（#{@makeup_slot.period_text}）を登録しました。"
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @makeup_slot = find_slot
    end

    def update
      @makeup_slot = find_slot
      @makeup_slot.assign_attributes(slot_params)

      if save(@makeup_slot)
        redirect_to teacher_makeup_slots_path, notice: "振替枠（#{@makeup_slot.period_text}）を更新しました。"
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    # これから受け付ける枠だけ。過去の枠や存在しない ID は、RecordNotFound になり、E-01（404）が表示される
    def find_slot
      slot = policy_scope(MakeupSlot).upcoming.find(params[:id])
      authorize slot
      slot
    end

    def slot_params
      params.expect(makeup_slot: %i[starts_at ends_at capacity])
    end

    # 検証のあと、保存の直前に、同じ時間の枠が登録されたときは、DB の排他制約が止める。そのときも、重なりのエラーとして表示する
    def save(slot)
      slot.save
    rescue ActiveRecord::StatementInvalid => e
      raise unless e.cause.is_a?(PG::ExclusionViolation)

      slot.errors.add(:base, "同じ時間に、ほかの振替枠が登録されました。時間を変えて、もう一度お試しください")
      false
    end
  end
end
