require "rails_helper"

RSpec.describe "振替枠の一覧（T-06）", type: :request do
  describe "GET /teacher/makeup_slots" do
    context "先生のとき" do
      before { sign_in create(:teacher) }

      def rows
        Nokogiri::HTML5.parse(response.body).css("tbody tr").map { |tr| tr.css("td")[0, 4].map { |td| td.text.strip } }
      end

      it "これからの振替枠を、日付順に、日付・時間・定員・予約数の欄で表示する" do
        travel_to Time.zone.local(2026, 6, 10, 12, 0) do
          create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 20, 10, 0), ends_at: Time.zone.local(2026, 6, 20, 10, 30), capacity: 2)
          create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 13, 15, 0), ends_at: Time.zone.local(2026, 6, 13, 15, 30), capacity: 1)

          get teacher_makeup_slots_path

          expect(response).to have_http_status :ok
          expect(response.body).to include "予約数"
          expect(rows).to eq [
            [ "2026年6月13日（土）", "15:00〜15:30", "1人", "0 / 1" ],
            [ "2026年6月20日（土）", "10:00〜10:30", "2人", "0 / 2" ]
          ]
        end
      end

      it "予約数を、キャンセル済みを数えずに「予約数 / 定員」で表示する（枠が複数でも N+1 を出さない）" do
        travel_to Time.zone.local(2026, 6, 10, 12, 0) do
          booked = create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 13, 15, 0), ends_at: Time.zone.local(2026, 6, 13, 15, 30), capacity: 3)
          canceled_only = create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 14, 15, 0), ends_at: Time.zone.local(2026, 6, 14, 15, 30), capacity: 2)
          # 固定枠は先生が1人なので、予約ごとに別の曜日の固定枠から振替権を作る
          credits = (1..4).map do |wday|
            lesson_slot = create(:lesson_slot, wday: wday)
            create(:makeup_credit, absence: create(:absence, lesson_slot: lesson_slot, lesson_on: Date.new(2099, 1, 4) + wday))
          end
          create(:makeup_reservation, makeup_slot: booked, makeup_credit: credits[0])
          create(:makeup_reservation, makeup_slot: booked, makeup_credit: credits[1])
          create(:makeup_reservation, :canceled, makeup_slot: booked, makeup_credit: credits[2])
          create(:makeup_reservation, :canceled, makeup_slot: canceled_only, makeup_credit: credits[3])
          create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 15, 15, 0), ends_at: Time.zone.local(2026, 6, 15, 15, 30), capacity: 1)

          get teacher_makeup_slots_path

          expect(rows.map(&:last)).to eq [ "2 / 3", "0 / 2", "0 / 1" ]
        end
      end

      it "過去の振替枠は表示しない（終了前の枠は、開始後でも表示する）" do
        travel_to Time.zone.local(2026, 6, 10, 12, 0) do
          create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 9, 10, 0), ends_at: Time.zone.local(2026, 6, 9, 10, 30))
          create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 10, 10, 0), ends_at: Time.zone.local(2026, 6, 10, 11, 0)) # 終了済み
          create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 10, 11, 0), ends_at: Time.zone.local(2026, 6, 10, 11, 45)) # 終了済み
          create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 10, 11, 45), ends_at: Time.zone.local(2026, 6, 10, 12, 15)) # 開催中
          create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 11, 10, 0), ends_at: Time.zone.local(2026, 6, 11, 10, 30))

          get teacher_makeup_slots_path

          expect(rows.map(&:second)).to eq %w[11:45〜12:15 10:00〜10:30]
        end
      end

      it "振替枠がないときは、その旨を表示する" do
        get teacher_makeup_slots_path

        expect(response.body).to include "これからの振替枠はありません。"
      end

      it "メニューに「振替枠」を表示する" do
        get teacher_makeup_slots_path

        expect(Nokogiri::HTML5.parse(response.body).css("a.nav-link").map(&:text)).to include "振替枠"
      end
    end

    context "保護者のとき" do
      before { sign_in create(:guardian) }

      it "一覧を表示せず、P-01 に戻してメッセージを表示する" do
        get teacher_makeup_slots_path

        expect(response).to redirect_to root_path
        follow_redirect!
        expect(response.body).to include "この画面を開く権限がありません。"
      end
    end

    context "ログインしていないとき" do
      it "C-01 に移動する" do
        get teacher_makeup_slots_path

        expect(response).to redirect_to new_user_session_path
      end
    end
  end

  describe "T-07 振替枠の登録" do
    let(:valid_params) do
      { makeup_slot: { starts_at: "2026-06-20T10:00", ends_at: "2026-06-20T10:30", capacity: "2" } }
    end

    context "先生のとき" do
      before { sign_in create(:teacher) }

      it "一覧に「振替枠を追加する」リンクがあり、定員の初期値が1のフォームを表示する" do
        get teacher_makeup_slots_path
        expect(response.body).to include "振替枠を追加する"

        get new_teacher_makeup_slot_path

        expect(response).to have_http_status :ok
        page = Nokogiri::HTML5.parse(response.body)
        expect(response.body).to include "開始日時", "終了日時", "定員", "保存する"
        expect(page.at_css("input[name='makeup_slot[capacity]']")["value"]).to eq "1"
      end

      it "登録すると、一覧（T-06）に表示される" do
        travel_to Time.zone.local(2026, 6, 10, 12, 0) do
          expect { post teacher_makeup_slots_path, params: valid_params }.to change(MakeupSlot, :count).by(1)

          expect(response).to redirect_to teacher_makeup_slots_path
          follow_redirect!
          expect(response.body).to include "振替枠（6月20日 10:00〜10:30）を登録しました。", "2026年6月20日（土）", "10:00〜10:30", "2人"
          expect(MakeupSlot.last.starts_at).to eq Time.zone.local(2026, 6, 20, 10, 0)
        end
      end

      it "入力エラーは、同じ画面の項目の下に表示し、入力値を残す" do
        expect {
          post teacher_makeup_slots_path, params: { makeup_slot: { starts_at: "", ends_at: "2026-06-20T10:00", capacity: "0" } }
        }.not_to change(MakeupSlot, :count)

        expect(response).to have_http_status :unprocessable_content
        page = Nokogiri::HTML5.parse(response.body)
        messages = page.css(".invalid-feedback").map { |node| node.text.strip }
        expect(messages).to include "開始日時を入力してください", "定員は1以上の値にしてください"
        expect(page.at_css("input[name='makeup_slot[ends_at]']")["value"]).to eq "2026-06-20T10:00"
      end

      it "終了日時が開始日時より前なら、エラーを表示する" do
        post teacher_makeup_slots_path, params: { makeup_slot: { starts_at: "2026-06-20T10:30", ends_at: "2026-06-20T10:00", capacity: "1" } }

        expect(response).to have_http_status :unprocessable_content
        expect(response.body).to include "終了日時は開始日時より後にしてください"
      end

      it "ほかの振替枠と重なるときは、どの枠と重なるかを、フォームの上に表示する" do
        create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 20, 10, 0), ends_at: Time.zone.local(2026, 6, 20, 11, 0))

        expect {
          post teacher_makeup_slots_path, params: { makeup_slot: { starts_at: "2026-06-20T10:30", ends_at: "2026-06-20T11:30", capacity: "1" } }
        }.not_to change(MakeupSlot, :count)

        expect(response).to have_http_status :unprocessable_content
        alert = Nokogiri::HTML5.parse(response.body).at_css(".alert-danger").text
        expect(alert).to include "同じ時間に、ほかの振替枠があります（6月20日 10:00〜11:00）"
      end

      it "固定枠のレッスンと重なるときは、どのレッスンと重なるかを表示する" do
        create(:lesson_slot, student: create(:student, name: "たろう"), wday: 6, start_time: "10:00", end_time: "10:30", starts_on: Date.new(2026, 1, 1))

        post teacher_makeup_slots_path, params: valid_params

        expect(response).to have_http_status :unprocessable_content
        expect(response.body).to include "固定枠（毎週のレッスン）の時間と重なっています（たろうさん 6月20日 10:00〜10:30）"
      end

      it "検証のあと、保存の直前に同じ時間の枠が登録されても、DB の排他制約で止まり、重なりのエラーを表示する" do
        competitor = create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 20, 10, 0), ends_at: Time.zone.local(2026, 6, 20, 11, 0))
        # 検証の時点では重なりが見えない状態にして、DB の制約まで進ませる
        allow_any_instance_of(MakeupSlot).to receive(:not_overlapping_other_makeup_slots) # rubocop:disable RSpec/AnyInstance

        expect { post teacher_makeup_slots_path, params: valid_params }.not_to change(MakeupSlot, :count)

        expect(response).to have_http_status :unprocessable_content
        expect(response.body).to include "同じ時間に、ほかの振替枠が登録されました"
        expect(competitor.reload).to be_persisted
      end
    end

    context "保護者のとき" do
      before { sign_in create(:guardian) }

      it "フォームを開けず、登録もできない" do
        get new_teacher_makeup_slot_path
        expect(response).to redirect_to root_path

        expect { post teacher_makeup_slots_path, params: valid_params }.not_to change(MakeupSlot, :count)
        expect(response).to redirect_to root_path
      end
    end

    context "ログインしていないとき" do
      it "C-01 に移動し、登録もできない" do
        get new_teacher_makeup_slot_path
        expect(response).to redirect_to new_user_session_path

        expect { post teacher_makeup_slots_path, params: valid_params }.not_to change(MakeupSlot, :count)
        expect(response).to redirect_to new_user_session_path
      end
    end
  end

  describe "T-07 振替枠の編集" do
    let!(:slot) { create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 20, 10, 0), ends_at: Time.zone.local(2026, 6, 20, 10, 30), capacity: 3) }
    let(:update_params) do
      { makeup_slot: { starts_at: "2026-06-20T14:00", ends_at: "2026-06-20T15:00", capacity: "2" } }
    end

    around { |example| travel_to(Time.zone.local(2026, 6, 10, 12, 0)) { example.run } }

    context "先生のとき" do
      before { sign_in create(:teacher) }

      it "一覧に編集のリンクがあり、現在の値が入ったフォームを表示する" do
        get teacher_makeup_slots_path
        expect(response.body).to include edit_teacher_makeup_slot_path(slot)

        get edit_teacher_makeup_slot_path(slot)

        expect(response).to have_http_status :ok
        page = Nokogiri::HTML5.parse(response.body)
        expect(page.at_css("input[name='makeup_slot[starts_at]']")["value"]).to eq "2026-06-20T10:00"
        expect(page.at_css("input[name='makeup_slot[capacity]']")["value"]).to eq "3"
      end

      it "更新して、一覧に戻る" do
        patch teacher_makeup_slot_path(slot), params: update_params

        expect(response).to redirect_to teacher_makeup_slots_path
        follow_redirect!
        expect(response.body).to include "振替枠（6月20日 14:00〜15:00）を更新しました。"
        expect(slot.reload).to have_attributes(starts_at: Time.zone.local(2026, 6, 20, 14, 0), capacity: 2)
      end

      it "自分自身の時間とは重ならない（同じ時間のまま、定員だけ変えられる）" do
        patch teacher_makeup_slot_path(slot), params: { makeup_slot: { starts_at: "2026-06-20T10:00", ends_at: "2026-06-20T10:30", capacity: "1" } }

        expect(response).to redirect_to teacher_makeup_slots_path
        expect(slot.reload.capacity).to eq 1
      end

      it "予約がある枠は、定員を予約数より少なくできない" do
        allow_any_instance_of(MakeupSlot).to receive(:reserved_count).and_return(2) # rubocop:disable RSpec/AnyInstance

        patch teacher_makeup_slot_path(slot), params: { makeup_slot: { capacity: "1" } }

        expect(response).to have_http_status :unprocessable_content
        expect(response.body).to include "定員は、すでにある予約の数（2件）以上にしてください"
        expect(slot.reload.capacity).to eq 3
      end

      it "ほかの振替枠と重なるときは、エラーを表示し、変更しない" do
        create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 20, 14, 0), ends_at: Time.zone.local(2026, 6, 20, 15, 0))

        patch teacher_makeup_slot_path(slot), params: update_params

        expect(response).to have_http_status :unprocessable_content
        expect(response.body).to include "同じ時間に、ほかの振替枠があります（6月20日 14:00〜15:00）"
        expect(slot.reload.starts_at).to eq Time.zone.local(2026, 6, 20, 10, 0)
      end

      it "過去の枠は、編集画面を開けず、404（E-01）になる" do
        past = create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 1, 10, 0), ends_at: Time.zone.local(2026, 6, 1, 10, 30))

        get edit_teacher_makeup_slot_path(past)

        expect(response).to have_http_status :not_found
      end

      it "存在しない枠は、404（E-01）になる" do
        patch teacher_makeup_slot_path(0), params: update_params

        expect(response).to have_http_status :not_found
      end
    end

    context "保護者のとき" do
      before { sign_in create(:guardian) }

      it "編集画面は開けず、更新もできない" do
        get edit_teacher_makeup_slot_path(slot)
        expect(response).to have_http_status :not_found
      end
    end

    context "ログインしていないとき" do
      it "C-01 に移動する" do
        get edit_teacher_makeup_slot_path(slot)

        expect(response).to redirect_to new_user_session_path
      end
    end
  end
end
