module ApplicationHelper
  # flash の種類を Bootstrap の alert の色に変換する
  FLASH_CLASSES = {
    "notice" => "alert-success",
    "alert" => "alert-danger"
  }.freeze

  def flash_class(type)
    FLASH_CLASSES.fetch(type.to_s, "alert-info")
  end

  # 入力エラーを項目の下に表示する（エラーがなければ何も表示しない）
  # 使い方：<%= f.text_field :name %><%= field_error(@student, :name) %>
  def field_error(record, attribute)
    messages = record.errors.full_messages_for(attribute)
    return if messages.empty?

    tag.div(safe_join(messages, tag.br), class: "invalid-feedback d-block")
  end
end
