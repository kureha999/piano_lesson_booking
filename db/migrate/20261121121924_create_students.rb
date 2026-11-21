class CreateStudents < ActiveRecord::Migration[8.1]
  def change
    create_table :students do |t|
      # 保護者（users）に属する。生徒はログインしないので、users には入れない
      t.references :guardian, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false # 呼び名

      t.timestamps
    end
  end
end
