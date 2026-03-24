require 'xcodeproj'

# Create project
project = Xcodeproj::Project.new('Pomodare.xcodeproj')

# Add macOS app target
target = project.new_target(:application, 'Pomodare', :osx, '14.0')

# Add main group structure
main_group = project.main_group.new_group('Pomodare')
models_group = main_group.new_group('Models')
views_group = main_group.new_group('Views')

# Files in Pomodare/ root:
root_files = ['PomodareApp.swift', 'AppDelegate.swift', 'Extensions.swift']

# Files in Pomodare/Models/:
model_files = ['AppState.swift', 'SupabaseService.swift', 'ActivityTracker.swift']

# Files in Pomodare/Views/:
view_files = ['MenuBarView.swift', 'ButtonStyles.swift', 'HomeView.swift', 'WaitingView.swift', 'SessionView.swift', 'ResultView.swift']

root_files.each do |f|
  path = "Pomodare/#{f}"
  next unless File.exist?(path)
  file_ref = main_group.new_file(path)
  target.add_file_references([file_ref])
end

model_files.each do |f|
  path = "Pomodare/Models/#{f}"
  next unless File.exist?(path)
  file_ref = models_group.new_file(path)
  target.add_file_references([file_ref])
end

view_files.each do |f|
  path = "Pomodare/Views/#{f}"
  next unless File.exist?(path)
  file_ref = views_group.new_file(path)
  target.add_file_references([file_ref])
end

# Add Info.plist
plist_ref = main_group.new_file('Pomodare/Info.plist')

# Build settings
target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = 'Pomodare'
  config.build_settings['SWIFT_VERSION'] = '5.9'
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  config.build_settings['INFOPLIST_FILE'] = 'Pomodare/Info.plist'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.aragosta.pomodare'
  config.build_settings['CODE_SIGN_IDENTITY'] = '-'
  config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  config.build_settings['ENABLE_HARDENED_RUNTIME'] = 'NO'
  config.build_settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
end

project.save
puts "Project generated: Pomodare.xcodeproj"
