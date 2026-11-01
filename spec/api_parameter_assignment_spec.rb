require 'logger'
require 'tiun'

RSpec.describe 'Tiun API parameter assignment' do
   let(:controller) { Object.new.extend(Tiun::Base) }
   let(:argument) { OpenStruct.new(name: 'language_code', alias: 'language, l', context: 'language', kind: 'string') }
   let(:configuration) { OpenStruct.new(args: [argument], contexted_attributes: {'language' => ['language_code', 'language', 'l']}.to_os) }

   before do
      allow(controller).to receive(:action_context).and_return(configuration)
      allow(controller).to receive(:action_name).and_return('create')
      allow(controller).to receive(:param_name).and_return('event')
      allow(controller).to receive(:permitted_children).and_return({})
   end

   it 'accepts context arguments without aliases' do
      value = Tiun.contexted_attributes_for([OpenStruct.new(name: 'language', context: true)])
      expect(value).to eq('language' => ['language'])
   end

   it 'normalizes a permitted alias and excludes undeclared parameters' do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(event: {l: 'ру', ignored: 'value'}))
      expect(controller.send(:current_attrs)).to eq('language_code' => 'ру')
   end

   it 'returns named context values with symbol keys' do
      expect(controller.send(:context_attributes, 'l' => 'ру')).to eq(language: 'ру')
   end

   it 'preserves false and omits absent context values' do
      expect(controller.send(:context_attributes, 'language_code' => false)).to eq(language: false)
      expect(controller.send(:context_attributes, {})).to eq({})
   end

   it 'stores unknown declared attributes as instance variables' do
      value = Object.new
      controller.send(:assign_attributes_for, value, 'place_uno' => 'Град')
      expect(value.instance_variable_get(:@place_uno)).to eq('Град')
      expect(value).not_to respond_to(:place_uno=)
   end

   it 'uses an existing setter without creating a duplicate instance variable' do
      value = Object.new
      stored = {}
      value.define_singleton_method(:language_code=) { |code| stored[:language_code] = code }
      allow(controller).to receive(:object).and_return(value)
      allow(controller).to receive(:current_attrs).and_return('language_code' => 'ру')
      controller.send(:assign_attributes)
      expect(stored).to eq(language_code: 'ру')
      expect(value.instance_variable_defined?(:@language_code)).to eq(false)
   end
   it 'prefers the canonical parameter when an alias is also supplied' do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(event: {language_code: 'ру', l: 'гр'}))
      expect(controller.send(:current_attrs)).to eq('language_code' => 'ру')
   end

   it 'applies a declared column filter once without invoking an unrelated alias scope' do
      model = Class.new
      model.define_singleton_method(:attribute_names) { ['type'] }
      model.define_singleton_method(:by_t) { raise 'The alias scope must not run' }
      allow(controller).to receive(:model).and_return(model)
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(t: 'Building'))
      relation = double('relation')
      filtered = double('filtered relation')
      expect(relation).to receive(:where).with({'type' => 'Building'}).and_return(filtered)
      expect(controller.send(:apply_by_names, ['type', 't'], relation, 't')).to equal(filtered)
   end

   it 'does not copy persisted model values into an absent request context' do
      value = Object.new
      value.define_singleton_method(:language_code) { 'гр' }
      expect(value).not_to receive(:language_code)
      allow(controller).to receive(:object).and_return(value)
      allow(controller).to receive(:current_attrs).and_return({})
      controller.send(:assign_attributes)
      expect(value.instance_variable_defined?(:@language_code)).to eq(false)
   end

   it 'applies configured defaults and lets request values override them' do
      value = Object.new
      allow(controller).to receive(:object).and_return(value)
      allow(controller).to receive(:default_attributes).and_return(place_uno: 'Иное', fallback: false)
      allow(controller).to receive(:current_attrs).and_return('place_uno' => 'Град')
      controller.send(:assign_attributes)
      expect(value.instance_variable_get(:@place_uno)).to eq('Град')
      expect(value.instance_variable_get(:@fallback)).to eq(false)
   end

   it 'passes only the permitted STI discriminator to the model constructor' do
      model = double('model', inheritance_column: 'type', column_names: ['id', 'type'])
      record = double('STI record')
      allow(controller).to receive(:model).and_return(model)
      allow(controller).to receive(:current_attrs).and_return('type' => 'Council', 'place_uno' => 'Град')
      expect(model).to receive(:new).with({'type' => 'Council'}).and_return(record)
      expect(controller.send(:new_object)).to equal(record)
   end

   it 'keeps a virtual type parameter out of STI selection' do
      model = double('model', inheritance_column: 'type', column_names: ['id'])
      record = double('record without STI')
      allow(controller).to receive(:model).and_return(model)
      allow(controller).to receive(:current_attrs).and_return('type' => 'Account::Email')
      expect(model).to receive(:new).with({}).and_return(record)
      expect(controller.send(:new_object)).to equal(record)
   end

end
