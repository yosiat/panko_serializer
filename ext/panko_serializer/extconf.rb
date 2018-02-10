# frozen_string_literal: true
require "mkmf"
require "pathname"

$CPPFLAGS += " -Wall"

extension_name = "panko_serializer"
dir_config(extension_name)

RbConfig.expand(srcdir = "$(srcdir)".dup)

# enum all source files
$srcs = Dir[File.join(srcdir, "**/*.c")]


# Get all source directories recursivley
directories = Dir[File.join(srcdir, "**/*")].select { |f| File.directory?(f) }
directories = directories.map { |d| Pathname.new(d).relative_path_from(Pathname.new(srcdir)) }
directories.each do |dir|
	# add include path to the internal folder
	# $(srcdir) is a root folder, where "extconf.rb" is stored
	$INCFLAGS << " -I$(srcdir)/#{dir}"

	# add folder, where compiler can search source files
	$VPATH << "$(srcdir)/#{dir}"
end

create_makefile("panko/panko_serializer")
