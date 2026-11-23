# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_23_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "lesson_slots", force: :cascade do |t|
    t.bigint "student_id", null: false
    t.integer "wday", null: false
    t.time "start_time", null: false
    t.time "end_time", null: false
    t.date "starts_on", null: false
    t.date "ends_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["student_id"], name: "index_lesson_slots_on_student_id"
    t.check_constraint "end_time > start_time", name: "lesson_slots_end_after_start"
    t.check_constraint "ends_on IS NULL OR ends_on >= starts_on", name: "lesson_slots_ends_on_after_starts_on"
    t.check_constraint "wday >= 0 AND wday <= 6", name: "lesson_slots_wday_range"
  end

  create_table "makeup_rules", force: :cascade do |t|
    t.integer "monthly_limit", default: 2, null: false
    t.integer "valid_days", default: 30, null: false
    t.integer "absence_deadline_hours", default: 2, null: false
    t.integer "reservation_deadline_days", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.check_constraint "absence_deadline_hours >= 0", name: "makeup_rules_absence_deadline_hours_non_negative"
    t.check_constraint "id = 1", name: "makeup_rules_single_row"
    t.check_constraint "monthly_limit >= 0", name: "makeup_rules_monthly_limit_non_negative"
    t.check_constraint "reservation_deadline_days >= 0", name: "makeup_rules_reservation_deadline_days_non_negative"
    t.check_constraint "valid_days >= 0", name: "makeup_rules_valid_days_non_negative"
  end

  create_table "makeup_slots", force: :cascade do |t|
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.integer "capacity", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false

    t.check_constraint "capacity >= 1", name: "makeup_slots_capacity_positive"
    t.check_constraint "ends_at > starts_at", name: "makeup_slots_ends_after_starts"
    t.exclusion_constraint "tsrange(starts_at, ends_at) WITH &&", using: :gist, name: "makeup_slots_no_overlap"
  end

  create_table "students", force: :cascade do |t|
    t.bigint "guardian_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["guardian_id"], name: "index_students_on_guardian_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name", null: false
    t.integer "role", default: 0, null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "invitation_token"
    t.datetime "invitation_created_at"
    t.datetime "invitation_sent_at"
    t.datetime "invitation_accepted_at"
    t.integer "invitation_limit"
    t.string "invited_by_type"
    t.bigint "invited_by_id"
    t.integer "invitations_count", default: 0
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["invitation_token"], name: "index_users_on_invitation_token", unique: true
    t.index ["invited_by_id"], name: "index_users_on_invited_by_id"
    t.index ["invited_by_type", "invited_by_id"], name: "index_users_on_invited_by"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role_teacher_only", unique: true, where: "(role = 1)"
  end

  add_foreign_key "lesson_slots", "students"
  add_foreign_key "students", "users", column: "guardian_id"
end
