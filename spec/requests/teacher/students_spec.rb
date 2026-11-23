require "rails_helper"

RSpec.describe "生徒の一覧・登録・編集（T-02・T-03）", type: :request do
  let(:valid_params) do
    { student: { name: "たろう", guardian_name: "山田花子", guardian_email: "hanako@example.com" } }
  end

  describe "GET /teacher/students（T-02 生徒一覧）" do
    context "先生のとき" do
      before { sign_in create(:teacher) }

      it "生徒名と保護者名を一覧で表示する" do
        yamada = create(:guardian, name: "山田花子")
        suzuki = create(:guardian, name: "鈴木一郎")
        create(:student, guardian: yamada, name: "たろう")
        create(:student, guardian: yamada, name: "はなこ")
        create(:student, guardian: suzuki, name: "ゆうき")

        get teacher_students_path

        expect(response).to have_http_status :ok
        rows = Nokogiri::HTML5.parse(response.body).css("tbody tr").map { |tr| tr.css("td")[0, 2].map { |td| td.text.strip } }
        expect(rows).to eq [ %w[たろう 山田花子], %w[はなこ 山田花子], %w[ゆうき 鈴木一郎] ]
      end

      it "生徒ごとに、今月の振替の利用回数（その月に振替権が付いた欠席の数）と上限を表示する" do
        travel_to Time.zone.local(2026, 11, 2, 9, 0)
        used = create(:student, name: "たろう")
        create(:student, name: "はなこ")
        slot = create(:lesson_slot, student: used, wday: 3, start_time: "16:00", end_time: "16:30")
        create(:absence, lesson_slot: slot, lesson_on: Date.new(2026, 11, 4), reported_by: used.guardian)
        create(:absence, :after_deadline, lesson_slot: slot, lesson_on: Date.new(2026, 11, 11), reported_by: used.guardian) # 数えない
        create(:absence, lesson_slot: slot, lesson_on: Date.new(2026, 12, 2), reported_by: used.guardian) # 来月（数えない）

        get teacher_students_path

        page = Nokogiri::HTML5.parse(response.body)
        expect(page.css("thead th").map { |th| th.text.strip }).to include "今月の振替の利用回数"
        expect(page.css("tbody tr").map { |tr| tr.css("td")[0, 3].map { |td| td.text.squish } }).to eq [
          [ "たろう", "保護者", "1回 （上限 2回）" ], [ "はなこ", "保護者", "0回 （上限 2回）" ]
        ]
      end

      it "月の上限は、先生が設定した値を表示する" do
        MakeupRule.current.update!(monthly_limit: 4)
        create(:student)

        get teacher_students_path

        expect(response.body).to include "0回"
        expect(response.body).to include "上限 4回"
      end

      it "生徒の追加・編集へのリンクを表示する" do
        student = create(:student)

        get teacher_students_path

        page = Nokogiri::HTML5.parse(response.body)
        expect(page.at_css("a[href='#{new_teacher_student_path}']").text).to eq "生徒を追加する"
        expect(page.at_css("a[href='#{edit_teacher_student_path(student)}']").text).to eq "編集"
      end

      it "生徒がいないときは、その旨を表示する" do
        get teacher_students_path

        expect(response.body).to include "まだ生徒が登録されていません。"
        expect(response.body).not_to include "<table"
      end

      it "メニューに「生徒」を表示する" do
        get teacher_students_path

        expect(Nokogiri::HTML5.parse(response.body).css("#main-menu .nav-link").map(&:text).map(&:strip))
          .to include "生徒"
      end
    end

    context "保護者のとき" do
      before { sign_in create(:guardian) }

      it "一覧を表示せず、P-01 に戻してメッセージを表示する" do
        create(:student, name: "ひみつ")

        get teacher_students_path

        expect(response).to redirect_to root_path
        follow_redirect!
        expect(response.body).to include "この画面を開く権限がありません。"
        expect(response.body).not_to include "ひみつ"
      end
    end

    context "ログインしていないとき" do
      it "C-01 に移動する" do
        get teacher_students_path

        expect(response).to redirect_to new_user_session_path
      end
    end
  end

  describe "T-03 生徒の登録" do
    context "先生のとき" do
      before { sign_in create(:teacher) }

      it "フォームを表示する" do
        get new_teacher_student_path

        expect(response).to have_http_status :ok
        expect(response.body).to include "生徒の呼び名", "保護者の名前", "保護者のメールアドレス", "登録する"
      end

      it "新しいメールアドレスなら、保護者を作ってから生徒を追加し、一覧に戻る" do
        expect { post teacher_students_path, params: valid_params }
          .to change(Student, :count).by(1).and change(User.guardian, :count).by(1)

        expect(response).to redirect_to teacher_students_path
        follow_redirect!
        expect(response.body).to include "たろうさんと保護者（山田花子さん）を登録しました。", "hanako@example.com に、パスワード設定の招待メールを送りました。"
      end

      it "新しい保護者に招待メールを1通送り、2人目の登録では送らない" do
        expect { post teacher_students_path, params: valid_params }
          .to change { ActionMailer::Base.deliveries.size }.by(1)

        new_scan("2人目の登録") # 登録ごとに別の scan にする
        expect {
          post teacher_students_path, params: { student: valid_params[:student].merge(name: "はなこ") }
        }.not_to change { ActionMailer::Base.deliveries.size }
        Prosopite.finish # ここから先は、テスト自身の確認のクエリなので、調べない
        expect(User.guardian.sole.invited_by).to eq User.teacher.sole
      end

      it "招待メールを送れなかったときは、登録はそのままで、パスワードを設定してもらう方法を伝える" do
        allow_any_instance_of(User).to receive(:deliver_invitation).and_raise(Net::SMTPFatalError, "送信エラー") # rubocop:disable RSpec/AnyInstance

        expect { post teacher_students_path, params: valid_params }.to change(Student, :count).by(1)

        follow_redirect!
        expect(response.body).to include "たろうさんと保護者（山田花子さん）を登録しました。", "招待メールを送れませんでした", "パスワードを忘れた方"
      end

      it "同じメールアドレスで2人目を登録すると、保護者は1人のまま、生徒が2人になる" do
        post teacher_students_path, params: valid_params
        expect {
          post teacher_students_path, params: { student: valid_params[:student].merge(name: "はなこ") }
        }.to change(Student, :count).by(1).and not_change(User.guardian, :count)

        follow_redirect!
        expect(response.body).to include "登録済みの保護者（山田花子さん）に、はなこさんを追加しました。"
        guardian = User.guardian.sole
        expect(guardian.students.pluck(:name)).to contain_exactly "たろう", "はなこ"
      end

      it "入力エラーは、同じ画面の項目の下に表示し、何も保存しない" do
        expect {
          post teacher_students_path, params: { student: { name: "", guardian_name: "", guardian_email: "abc" } }
        }.not_to change { [ User.count, Student.count ] }

        expect(response).to have_http_status :unprocessable_content
        page = Nokogiri::HTML5.parse(response.body)
        messages = page.css(".invalid-feedback").map { |node| node.text.strip }
        expect(messages).to include "生徒の呼び名を入力してください", "保護者の名前を入力してください"
        expect(messages.size).to eq 3
        expect(page.at_css("input[name='student[guardian_email]']")["value"]).to eq "abc"
      end

      it "先生のメールアドレスは使えない" do
        post teacher_students_path, params: { student: valid_params[:student].merge(guardian_email: User.teacher.sole.email) }

        expect(response).to have_http_status :unprocessable_content
        expect(response.body).to include "先生のメールアドレスです"
      end
    end

    context "保護者のとき" do
      before { sign_in create(:guardian) }

      it "フォームを開けない" do
        get new_teacher_student_path

        expect(response).to redirect_to root_path
      end

      it "登録できない" do
        expect { post teacher_students_path, params: valid_params }.not_to change { [ User.count, Student.count ] }

        expect(response).to redirect_to root_path
      end
    end

    context "ログインしていないとき" do
      it "C-01 に移動し、登録もできない" do
        get new_teacher_student_path
        expect(response).to redirect_to new_user_session_path

        expect { post teacher_students_path, params: valid_params }.not_to change(User, :count)
        expect(response).to redirect_to new_user_session_path
      end
    end
  end

  describe "T-03 生徒の編集" do
    let!(:student) { create(:student, name: "たろう", guardian: create(:guardian, name: "山田花子", email: "hanako@example.com")) }

    context "先生のとき" do
      before { sign_in create(:teacher) }

      it "現在の値が入ったフォームを表示する" do
        get edit_teacher_student_path(student)

        page = Nokogiri::HTML5.parse(response.body)
        expect(page.at_css("input[name='student[name]']")["value"]).to eq "たろう"
        expect(page.at_css("input[name='student[guardian_name]']")["value"]).to eq "山田花子"
        expect(page.at_css("input[name='student[guardian_email]']")["value"]).to eq "hanako@example.com"
      end

      it "更新して、一覧に戻る" do
        patch teacher_student_path(student), params: { student: { name: "たろ", guardian_name: "山田はな", guardian_email: "hanako@example.com" } }

        expect(response).to redirect_to teacher_students_path
        follow_redirect!
        expect(response.body).to include "たろさんの情報を更新しました。"
        expect(student.reload.name).to eq "たろ"
        expect(student.guardian.name).to eq "山田はな"
      end

      it "入力エラーは、同じ画面の項目の下に表示する" do
        patch teacher_student_path(student), params: { student: { name: "", guardian_name: "山田花子", guardian_email: "hanako@example.com" } }

        expect(response).to have_http_status :unprocessable_content
        expect(response.body).to include "生徒の呼び名を入力してください"
        expect(student.reload.name).to eq "たろう"
      end

      it "存在しない生徒は、404（E-01）になる" do
        get edit_teacher_student_path(id: 0)

        expect(response).to have_http_status :not_found
      end
    end

    context "保護者のとき" do
      before { sign_in student.guardian }

      it "自分の子どもでも、編集画面は開けず、更新もできない" do
        get edit_teacher_student_path(student)
        expect(response).to redirect_to root_path

        patch teacher_student_path(student), params: { student: { name: "変更", guardian_name: "山田花子", guardian_email: "hanako@example.com" } }
        expect(response).to redirect_to root_path
        expect(student.reload.name).to eq "たろう"
      end

      it "ほかの家庭の生徒は、404（E-01）になり、存在することも伝えない" do
        other = create(:student)

        get edit_teacher_student_path(other)

        expect(response).to have_http_status :not_found
      end
    end

    context "ログインしていないとき" do
      it "C-01 に移動する" do
        get edit_teacher_student_path(student)

        expect(response).to redirect_to new_user_session_path
      end
    end
  end
end
