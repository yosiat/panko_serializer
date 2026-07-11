# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "panko/code_gen"
require "nested_composition"
require "recursive_self"
require "recursive_mutual"

# Feature-tier coverage for the multi-file +Dump+ fan-out per S15.5
# (issue #78). The flat single-file path lands in S15.2 / S15.4; this
# spec exercises the fan-out path: nested +Composition+,
# self-recursive +Descriptors+ (one file, +@x_serializer = self+),
# and mutually-recursive +Descriptors+ (two files with mutual
# +require_relative+). Asserts the on-disk layout, the
# +require_relative+ wiring, and that the dumped tree round-trips
# +require+ → +.new(descriptor: ...)+ → +serialize_one+ to the
# expected output.
RSpec.describe "Panko::CodeGen.dump (multi-file fan-out)" do
  describe "Fixtures::NestedComposition — one file per Generated Class" do
    let(:descriptor) { Fixtures::NestedComposition::DESCRIPTOR }
    let(:config) { Fixtures::NestedComposition::CONFIG }
    let(:sanity_record) { Fixtures::NestedComposition.sanity_record }

    it "writes 3 files to the same directory under deterministic basenames" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "nested_composition_post_serializer_json.rb")
        Panko::CodeGen.dump(descriptor, output: :json, config: config, path: target)

        expect(Dir.children(dir).sort).to eq(%w[
          nested_composition_author_serializer_json.rb
          nested_composition_comment_serializer_json.rb
          nested_composition_post_serializer_json.rb
        ])
      end
    end

    it "emits require_relative directives in the outer file pointing at sibling basenames" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "nested_composition_post_serializer_json.rb")
        Panko::CodeGen.dump(descriptor, output: :json, config: config, path: target)

        outer_source = File.read(target)
        expect(outer_source).to include(%(require_relative "nested_composition_author_serializer_json"))
        expect(outer_source).to include(%(require_relative "nested_composition_comment_serializer_json"))
      end
    end

    it "puts frozen_string_literal: true at line 1 of every dumped file" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "nested_composition_post_serializer_json.rb")
        Panko::CodeGen.dump(descriptor, output: :json, config: config, path: target)

        Dir.children(dir).each do |basename|
          first_line = File.open(File.join(dir, basename), &:readline)
          expect(first_line).to eq("# frozen_string_literal: true\n"), "missing pragma in #{basename}"
        end
      end
    end

    it "dumped tree round-trips through require + .new(descriptor:) + serialize_one" do
      # Rename every Descriptor in the tree so the require'd dumped
      # tree's constants do not collide with the snapshot tier's load
      # of +nested_composition_json.rb+ (same process).
      author = Panko::CodeGen::Descriptor.new(
        name: "S15FiveNestedAuthor",
        model: nil,
        attributes: Fixtures::NestedComposition::AUTHOR_DESCRIPTOR.attributes,
        method_attributes: [],
        associations: []
      )
      comment = Panko::CodeGen::Descriptor.new(
        name: "S15FiveNestedComment",
        model: nil,
        attributes: Fixtures::NestedComposition::COMMENT_DESCRIPTOR.attributes,
        method_attributes: [],
        associations: []
      )
      renamed = Panko::CodeGen::Descriptor.new(
        name: "S15FiveNestedPost",
        model: nil,
        attributes: descriptor.attributes,
        method_attributes: [],
        associations: [
          Panko::CodeGen::Association.new(
            name: :author, kind: :has_one, descriptor: author,
            if: ->(_record, _context) { true }
          ),
          Panko::CodeGen::Association.new(
            name: :comments, kind: :has_many, descriptor: comment
          )
        ]
      )

      Dir.mktmpdir do |dir|
        outer_path = File.join(dir, "s15_five_nested_post_json.rb")
        Panko::CodeGen.dump(renamed, output: :json, config: config, path: outer_path)
        require outer_path
        klass = Object.const_get(:S15FiveNestedPost_JSON)
        instance = klass.new(descriptor: renamed)
        expect(instance.serialize_one(sanity_record)).to eq(Fixtures::NestedComposition.expected_output(:json))
      end
    end

    it "two successive dumps to fresh dirs produce byte-identical files (deterministic)" do
      first = Dir.mktmpdir do |dir|
        target = File.join(dir, "nested_composition_post_serializer_json.rb")
        Panko::CodeGen.dump(descriptor, output: :json, config: config, path: target)
        Dir.children(dir).sort.to_h { |b| [b, File.read(File.join(dir, b))] }
      end
      second = Dir.mktmpdir do |dir|
        target = File.join(dir, "nested_composition_post_serializer_json.rb")
        Panko::CodeGen.dump(descriptor, output: :json, config: config, path: target)
        Dir.children(dir).sort.to_h { |b| [b, File.read(File.join(dir, b))] }
      end
      expect(first).to eq(second)
    end
  end

  describe "Fixtures::RecursiveSelf — one file, no require_relative for the self-loop" do
    let(:descriptor) { Fixtures::RecursiveSelf::DESCRIPTOR }
    let(:config) { Fixtures::RecursiveSelf::CONFIG }

    it "writes exactly one file" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "recursive_self_comment_serializer_json.rb")
        Panko::CodeGen.dump(descriptor, output: :json, config: config, path: target)
        expect(Dir.children(dir)).to eq(%w[recursive_self_comment_serializer_json.rb])
      end
    end

    it "emits no executable require_relative directives (self-loop handled by @<n>_serializer = self)" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "recursive_self_comment_serializer_json.rb")
        Panko::CodeGen.dump(descriptor, output: :json, config: config, path: target)

        executable_lines = File.read(target).each_line.reject { |l| l.lstrip.start_with?("#") }
        expect(executable_lines.grep(/^\s*require_relative\b/)).to be_empty
        expect(File.read(target)).to include("@replies_serializer = self")
      end
    end
  end

  describe "Fixtures::RecursiveMutual — two files with mutual require_relative" do
    let(:descriptor) { Fixtures::RecursiveMutual::DESCRIPTOR }
    let(:config) { Fixtures::RecursiveMutual::CONFIG }

    it "writes 2 files, one per Generated Class" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "recursive_mutual_folder_serializer_json.rb")
        Panko::CodeGen.dump(descriptor, output: :json, config: config, path: target)

        expect(Dir.children(dir).sort).to eq(%w[
          recursive_mutual_folder_serializer_json.rb
          recursive_mutual_item_serializer_json.rb
        ])
      end
    end

    it "emits require_relative pointing at the peer in each file" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "recursive_mutual_folder_serializer_json.rb")
        Panko::CodeGen.dump(descriptor, output: :json, config: config, path: target)

        folder = File.read(File.join(dir, "recursive_mutual_folder_serializer_json.rb"))
        item = File.read(File.join(dir, "recursive_mutual_item_serializer_json.rb"))

        expect(folder).to include(%(require_relative "recursive_mutual_item_serializer_json"))
        expect(item).to include(%(require_relative "recursive_mutual_folder_serializer_json"))
      end
    end

    it "round-trips through require + .new(descriptor:) + serialize_one for the cycle" do
      sanity_record = Fixtures::RecursiveMutual.sanity_record
      expected = Fixtures::RecursiveMutual.expected_output(:json)

      Dir.mktmpdir do |dir|
        # Rename both peers so const collisions with the snapshot tier
        # (which loads recursive_mutual_json.rb's combined form) cannot
        # occur in the same process.
        renamed_item = Panko::CodeGen::Descriptor.new(
          name: "S15FiveMutualItem",
          model: nil,
          attributes: Fixtures::RecursiveMutual::ITEM_DESCRIPTOR.attributes,
          method_attributes: [],
          associations: []
        )
        renamed_folder = Panko::CodeGen::Descriptor.new(
          name: "S15FiveMutualFolder",
          model: nil,
          attributes: Fixtures::RecursiveMutual::FOLDER_DESCRIPTOR.attributes,
          method_attributes: [],
          associations: []
        )
        renamed_folder.associations << Panko::CodeGen::Association.new(
          name: :items, kind: :has_many, descriptor: renamed_item
        )
        renamed_item.associations << Panko::CodeGen::Association.new(
          name: :subfolder, kind: :has_one, descriptor: renamed_folder
        )

        target = File.join(dir, "s15_five_mutual_folder_json.rb")
        Panko::CodeGen.dump(renamed_folder, output: :json, config: config, path: target)

        # Mutual +require_relative+ trips Ruby's "circular require
        # considered harmful" warning by design — both files name each
        # other, and the cycle is intentionally resolved at instantiation,
        # not load (per +docs/dumping.md § Nested Descriptor dumps+).
        # Silence just this require so the spec output stays clean.
        previous_verbose = $VERBOSE
        $VERBOSE = nil
        begin
          require target
        ensure
          $VERBOSE = previous_verbose
        end
        klass = Object.const_get(:S15FiveMutualFolder_JSON)
        instance = klass.new(descriptor: renamed_folder)
        expect(instance.serialize_one(sanity_record)).to eq(expected)
      end
    end
  end

  describe "outer-file path: argument is honored verbatim" do
    let(:descriptor) { Fixtures::NestedComposition::DESCRIPTOR }
    let(:config) { Fixtures::NestedComposition::CONFIG }

    it "writes the outer Generated Class to the caller-supplied path: even when it doesn't follow the snake_case convention" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "an_arbitrary_name.rb")
        Panko::CodeGen.dump(descriptor, output: :json, config: config, path: target)

        expect(File).to exist(target)
        expect(File.read(target)).to include("class NestedCompositionPostSerializer_JSON")
      end
    end

    it "places sibling inner files in the same directory regardless of the outer file's basename" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "an_arbitrary_name.rb")
        Panko::CodeGen.dump(descriptor, output: :json, config: config, path: target)

        expect(Dir.children(dir).sort).to eq(%w[
          an_arbitrary_name.rb
          nested_composition_author_serializer_json.rb
          nested_composition_comment_serializer_json.rb
        ])
      end
    end

    it "returns the caller-supplied path: from #dump" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "explicit_outer.rb")
        result = Panko::CodeGen.dump(descriptor, output: :json, config: config, path: target)
        expect(result).to eq(target)
      end
    end
  end
end
