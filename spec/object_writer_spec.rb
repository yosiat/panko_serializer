require 'spec_helper'

RSpec.describe Panko::ObjectWriter do

  it 'pushes object' do
    writer = Panko::ObjectWriter.new

    writer.push_object
    writer.push_value 1, 'id'
    writer.push_value 'Yosi', 'name'
    writer.pop

    expect(writer.output).to eq({
      'id' => 1,
      'name' => 'Yosi'
    })
  end

  it 'push key and value' do
    writer = Panko::ObjectWriter.new

    writer.push_object
    writer.push_key 'id'
    writer.push_value 1
    writer.pop

    expect(writer.output).to eq({
      'id' => 1
    })
  end

  it 'push key with object inside' do
    writer = Panko::ObjectWriter.new

    writer.push_object

    writer.push_key 'person'
    writer.push_object
    writer.push_value 1, 'id'
    writer.pop

    writer.pop

    expect(writer.output).to eq({
      'person' => {
        'id' => 1
      }
    })
  end


  it 'pushes array with objects' do
    writer = Panko::ObjectWriter.new

    writer.push_array
    writer.push_object
    writer.push_value 1, 'id'
    writer.push_value 1, 'id'
    writer.push_value 'Yosi', 'name'
    writer.pop
    writer.pop

    expect(writer.output).to eq([{
      'id' => 1,
      'name' => 'Yosi'
    }])
  end

  it 'pushes entries to array' do
    writer = Panko::ObjectWriter.new

    writer.push_array
    writer.push_value 1
    writer.push_value 2
    writer.pop

    expect(writer.output).to eq([1, 2])
  end
end
