# frozen_string_literal: true
require "mkmf"
require "pathname"

$CPPFLAGS += " -Wall"

extension_name = "panko_serializer"
dir_config(extension_name)

RbConfig.expand(srcdir = "$(srcdir)".dup)

# enum all source files
$srcs = Dir[File.join(srcdir, "**/*.c")]


directories = Pathname.new(srcdir).children.select { |c| c.directory? }.map(&:basename)
directories.each do |dir|
	# add include path to the internal folder
	# $(srcdir) is a root folder, where "extconf.rb" is stored
	$INCFLAGS << " -I$(srcdir)/#{dir}"

	# add folder, where compiler can search source files
	$VPATH << "$(srcdir)/#{dir}"
end

create_makefile("panko/panko_serializer")
