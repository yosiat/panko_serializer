require 'mkmf'

$CPPFLAGS += " -Wall"

extension_name = 'panko'
dir_config(extension_name)
create_makefile(extension_name)
%x{make clean}
