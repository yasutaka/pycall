require 'spec_helper'

module PyCall
  ::RSpec.describe PyPtr do
    let(:null) { PyPtr.null }
    let(:none) { PyPtr.none }

    describe '.null' do
      subject { null }
      it { is_expected.to be_null }
      it { is_expected.not_to be_none }
      it { is_expected.to eq(PyPtr.null) }
      it { is_expected.not_to equal(PyPtr.null) }
      specify { expect(subject.__address__).to eq(FFI::Pointer::NULL.address) }
      specify { expect(subject.__refcnt__).to eq(nil) }
    end

    describe '.none' do
      subject { none }
      it { is_expected.not_to be_null }
      it { is_expected.to be_none }
      it { is_expected.to eq(PyPtr.none) }
      it { is_expected.not_to equal(PyPtr.none) }
      specify { expect(subject.__address__).not_to eq(FFI::Pointer::NULL.address) }
      specify { expect(subject.__refcnt__).not_to eq(nil) }
    end

    describe '#initialize_copy' do
      let(:pyptr) { PyCall.eval('object()').__pyobj__ }

      specify do
        before_addr = pyptr.__address__
        before_refcnt = pyptr.__refcnt__

        duped = pyptr.dup
        expect(duped.__address__).to eq(before_addr)
        expect(pyptr.__address__).to eq(before_addr)
        expect(pyptr.__refcnt__).to eq(before_refcnt + 1)
        expect(pyptr.__refcnt__).to eq(duped.__refcnt__)
      end
    end
  end
end
