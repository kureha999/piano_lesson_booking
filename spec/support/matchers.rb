# change(...).by(0) の代わりに、「変わらないこと」を not_change(...) と書けるようにする
# 例：expect { ... }.to change(Student, :count).by(1).and not_change(User, :count)
RSpec::Matchers.define_negated_matcher :not_change, :change
