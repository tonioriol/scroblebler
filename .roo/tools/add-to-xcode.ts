import { z } from 'zod';
import { execSync } from 'child_process';

const tool = {
  name: "add_files_to_xcode",
  description: "Add or remove Swift files from Xcode project using xcodeproj Ruby gem",
  parameters: z.object({
    projectPath: z.string().describe("Path to .xcodeproj directory"),
    targetName: z.string().describe("Name of the target to modify"),
    action: z.enum(['add', 'remove']).describe("Action to perform: 'add' or 'remove'"),
    files: z.array(z.object({
      path: z.string().describe("Relative path to the file within the project"),
      group: z.string().optional().describe("Group path in Xcode (e.g., 'Scroblebler/Services') - required for add action, ignored for remove"),
    })).describe("Array of files to add or remove"),
  }),
  
  async execute({ projectPath, targetName, action, files }: {
    projectPath: string;
    targetName: string;
    action: 'add' | 'remove';
    files: Array<{ path: string; group?: string }>
  }) {
    try {
      // First check if xcodeproj gem is installed
      try {
        execSync('gem list xcodeproj -i', { encoding: 'utf-8' });
      } catch {
        return "Error: xcodeproj gem not installed. Run: gem install xcodeproj --user-install";
      }

      let rubyScript: string;
      
      if (action === 'add') {
        // Build the Ruby script for adding files
        const filesArray = files.map(f => `{ path: '${f.path}', group: '${f.group || ''}' }`).join(', ');
        
        rubyScript = `
require 'xcodeproj'

project = Xcodeproj::Project.open('${projectPath}')
target = project.targets.find { |t| t.name == '${targetName}' }

if target.nil?
  puts "Error: Target '${targetName}' not found"
  exit 1
end

files = [${filesArray}]

files.each do |file_info|
  # Find or create the group
  group = project.main_group.find_subpath(file_info[:group], true)
  
  # Create file reference with relative path from project root
  file_ref = group.new_reference(file_info[:path])
  
  # Add to compile sources build phase
  target.source_build_phase.add_file_reference(file_ref)
  
  puts "Added: #{file_info[:path]}"
end

project.save
puts "Success: All files added to Xcode project"
        `.trim();
      } else {
        // Build the Ruby script for removing files
        const filePaths = files.map(f => `'${f.path}'`).join(', ');
        
        rubyScript = `
require 'xcodeproj'

project = Xcodeproj::Project.open('${projectPath}')
target = project.targets.find { |t| t.name == '${targetName}' }

if target.nil?
  puts "Error: Target '${targetName}' not found"
  exit 1
end

file_paths = [${filePaths}]

file_paths.each do |file_path|
  # Find all file references matching this path
  file_refs = project.files.select { |f| f.path&.end_with?(file_path) || f.real_path&.to_s&.end_with?(file_path) }
  
  if file_refs.empty?
    puts "Warning: File not found in project: #{file_path}"
    next
  end
  
  file_refs.each do |file_ref|
    # Remove from build phases
    target.source_build_phase.files.each do |build_file|
      if build_file.file_ref == file_ref
        target.source_build_phase.files.delete(build_file)
      end
    end
    
    # Remove the file reference itself
    file_ref.remove_from_project
    
    puts "Removed: #{file_path}"
  end
end

project.save
puts "Success: All files removed from Xcode project"
        `.trim();
      }

      // Execute the Ruby script from the workspace directory
      const result = execSync(`cd /Users/tr0n/Code/scroblebler && ruby -e "${rubyScript.replace(/"/g, '\\"')}"`, {
        encoding: 'utf-8',
      });

      return result;
    } catch (error) {
      return `Error: ${error instanceof Error ? error.message : String(error)}`;
    }
  }
};

export default tool;
