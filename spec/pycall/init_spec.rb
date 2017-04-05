require 'spec_helper'

RSpec.describe PyCall do
  describe '.__main_dict__' do
    subject(:__main_dict__) { PyCall.__main_dict__ }

    specify 'refcnt >= 2' do
      expect(__main_dict__.__refcnt__).to be >= 2
    end
  end
end
