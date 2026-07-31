#!/usr/bin/env ruby

include RBA

input = $input
output = $output
macro = $macro

raise "input is required" if input.nil? || input.empty?
raise "output is required" if output.nil? || output.empty?
raise "macro is required" if macro.nil? || macro.empty?

layout = Layout.new
layout.read(input)
cell = layout.cell(macro)
raise "macro cell not found: #{macro}" if cell.nil?

instances = cell.child_instances
cell.clear
layout.cleanup

puts "blackboxed_macro=#{macro} removed_child_instances=#{instances} removed_internal_shapes=true"
layout.write(output)
