# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "sti_specialized"

RSpec.describe "Generated Class for Fixtures::StiSpecialized" do
  let(:descriptor) { Fixtures::StiSpecialized::DESCRIPTOR }
  let(:config) { Fixtures::StiSpecialized::CONFIG }

  describe "#serialize_one — STI intersection through the Specialized path" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:generated_class) { Panko::CodeGen.compile(descriptor, output: mode, config: config) }
        let(:generated) { generated_class.new(descriptor: descriptor) }

        it "reads the uniformly column-backed Attribute (vin) from the column on a Vehicle instance" do
          vehicle = Vehicle.create!(vin: "ABC123", make: "FORD")
          output = generated.serialize_one(vehicle)
          case mode
          when :json then expect(output).to include(%("vin":"ABC123"))
          when :hash then expect(output["vin"]).to eq("ABC123")
          end
        end

        it "reads the uniformly column-backed Attribute (vin) from the column on a Car instance" do
          car = Car.create!(vin: "XYZ789", make: "FORD")
          output = generated.serialize_one(car)
          case mode
          when :json then expect(output).to include(%("vin":"XYZ789"))
          when :hash then expect(output["vin"]).to eq("XYZ789")
          end
        end

        it "honors Car's titleize override on the downgraded Attribute (make) — DB value FORD emits Ford" do
          # The downgrade rule: +Car+ overrides +make+ → multi-class
          # intersection is +:method+ → emit +record.make+ → on a +Car+
          # the override (+super.titleize+) runs.
          car = Car.create!(vin: "XYZ789", make: "FORD")
          output = generated.serialize_one(car)
          case mode
          when :json then expect(output).to include(%("make":"Ford"))
          when :hash then expect(output["make"]).to eq("Ford")
          end
        end

        it "emits the raw column value for the downgraded Attribute (make) on a Vehicle — no parent override" do
          # Same emit form (+record.make+) but +Vehicle+ has no override,
          # so AR's auto-generated reader returns the raw column value.
          # This is the load-bearing claim: one straight-line +_write_one+
          # / +_to_hash+ serves both classes correctly.
          vehicle = Vehicle.create!(vin: "ABC123", make: "FORD")
          output = generated.serialize_one(vehicle)
          case mode
          when :json then expect(output).to include(%("make":"FORD"))
          when :hash then expect(output["make"]).to eq("FORD")
          end
        end

        it "serializes both a Vehicle and a Car through the same Generated Class" do
          # The single Generated Class is reused across both STI classes —
          # no per-class dispatch, no runtime classification. Both
          # instances pass through one +_write_one+ / +_to_hash+.
          vehicle = Vehicle.create!(vin: "ABC123", make: "FORD")
          car = Car.create!(vin: "XYZ789", make: "FORD")
          vehicle_out = generated.serialize_one(vehicle)
          car_out = generated.serialize_one(car)
          expected_vehicle = case mode
          when :json then '{"vin":"ABC123","make":"FORD"}'
          when :hash then {"vin" => "ABC123", "make" => "FORD"}
          end
          expected_car = case mode
          when :json then '{"vin":"XYZ789","make":"Ford"}'
          when :hash then {"vin" => "XYZ789", "make" => "Ford"}
          end
          expect(vehicle_out).to eq(expected_vehicle)
          expect(car_out).to eq(expected_car)
        end

        it "emits both Vehicle and Car in a single serialize_many call" do
          vehicle = Vehicle.create!(vin: "ABC123", make: "FORD")
          car = Car.create!(vin: "XYZ789", make: "FORD")
          output = generated.serialize_many([vehicle, car])
          case mode
          when :json
            expect(output).to eq('[{"vin":"ABC123","make":"FORD"},{"vin":"XYZ789","make":"Ford"}]')
          when :hash
            expect(output).to eq([
              {"vin" => "ABC123", "make" => "FORD"},
              {"vin" => "XYZ789", "make" => "Ford"}
            ])
          end
        end
      end
    end
  end

  describe ".compile — Specialized path emits a single _write_one / _to_hash without the Hash branch" do
    it "JSON mode: instance methods include _write_one but not _write_one_hash / _write_one_object" do
      generated_class = Panko::CodeGen.compile(descriptor, output: :json, config: config)
      method_names = generated_class.instance_methods(false)
      expect(method_names).to include(:_write_one)
      expect(method_names).not_to include(:_write_one_hash)
      expect(method_names).not_to include(:_write_one_object)
    end

    it "Hash mode: instance methods include _to_hash but not _to_hash_hash / _to_hash_object" do
      generated_class = Panko::CodeGen.compile(descriptor, output: :hash, config: config)
      method_names = generated_class.instance_methods(false)
      expect(method_names).to include(:_to_hash)
      expect(method_names).not_to include(:_to_hash_hash)
      expect(method_names).not_to include(:_to_hash_object)
    end
  end
end
