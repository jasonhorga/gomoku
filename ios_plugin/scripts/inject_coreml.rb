#!/usr/bin/env ruby
# Post-Godot-export xcodeproj patcher: adds GomokuNet.mlmodelc to the
# bundle resources and links CoreML.framework. Called from ios.yml
# after `godot --export-release` and before `fastlane beta`.
#
# Godot 4.5's iOS exporter doesn't know about arbitrary file resources
# or extra frameworks; the .gdextension file covers the plugin's static
# library but not CoreML itself. Rather than regex-patching the
# .pbxproj (brittle), we use the same `xcodeproj` gem fastlane already
# pulls in.
#
# Usage:
#   ruby inject_coreml.rb <path-to-gomoku.xcodeproj> <path-to-mlmodelc>
#
# The script is idempotent: re-running won't duplicate entries.

require "xcodeproj"
require "fileutils"

proj_path  = ARGV[0] or abort("missing xcodeproj path")
model_path = ARGV[1] or abort("missing mlmodelc path")

abort("xcodeproj not found: #{proj_path}") unless File.exist?(proj_path)
abort("mlmodelc not found: #{model_path}") unless File.exist?(model_path)

proj = Xcodeproj::Project.open(proj_path)
target = proj.targets.find { |t| t.name == "gomoku" } || proj.targets.first
abort("no target in #{proj_path}") unless target

# --- 1. Copy the .mlmodelc next to the xcodeproj so the reference is
#        a stable relative path that survives archive-time sandboxing.
proj_dir  = File.dirname(proj_path)
model_name = File.basename(model_path)
dest = File.join(proj_dir, model_name)
FileUtils.rm_rf(dest) if File.exist?(dest)
FileUtils.cp_r(model_path, dest)
puts "Copied #{model_path} -> #{dest}"

# --- 2. Add the .mlmodelc as a folder reference (so Xcode treats it
#        as an opaque resource directory, not a source tree) and put
#        it in Copy Bundle Resources.
existing = proj.main_group.files.find { |f| f.path == model_name }
if existing
  puts "mlmodelc already referenced — skipping re-add"
  ref = existing
else
  # new_reference keeps the directory as a single entity; Xcode won't
  # try to compile its contents. Using new_file would treat the dir as
  # a group of files, which is wrong for .mlmodelc.
  ref = proj.main_group.new_reference(model_name)
end

# Force it to be treated as a folder reference (blue folder), not a
# group. Xcodeproj gem's default new_reference picks this up from the
# path extension in most cases, but be explicit.
ref.last_known_file_type = "folder"

resources_phase = target.resources_build_phase
unless resources_phase.files_references.include?(ref)
  resources_phase.add_file_reference(ref)
  puts "Added #{model_name} to Copy Bundle Resources"
end

# --- 3. Link CoreML.framework. Godot's iOS template doesn't include it.
#        Swift's autolink hints might pick it up via swiftc, but being
#        explicit avoids a late link-time surprise.
frameworks_phase = target.frameworks_build_phase
framework_name = "CoreML.framework"
already_linked = frameworks_phase.files_references.any? { |f| f.path&.end_with?(framework_name) }

unless already_linked
  frameworks_group = proj.frameworks_group || proj.new_group("Frameworks")
  # SDKROOT-based relative path — SDK resolver finds CoreML under
  # /Applications/Xcode*/Contents/Developer/Platforms/iPhoneOS.platform.
  fw_ref = frameworks_group.new_file(
    "System/Library/Frameworks/#{framework_name}")
  fw_ref.source_tree = "SDKROOT"
  frameworks_phase.add_file_reference(fw_ref)
  puts "Linked #{framework_name}"
end

proj.save
puts "Saved #{proj_path}"
