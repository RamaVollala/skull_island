# frozen_string_literal: true

# Internal requirements
require 'skull_island'

# External requirements
require 'yaml'
require 'thor'

module SkullIsland
  # Base CLI for SkullIsland
  class CLI < Thor
    include Helpers::Migration

    class_option :verbose, type: :boolean

    desc 'export [OPTIONS] [OUTPUT|-]', 'Export the current configuration to OUTPUT'
    def export(output_file = '-')
      if output_file == '-'
        STDERR.puts '[INFO] Outputting to STDOUT' if options['verbose']
      else
        full_filename = File.expand_path(output_file)
        dirname = File.dirname(full_filename)
        unless File.exist?(dirname) && File.ftype(dirname) == 'directory'
          raise Exceptions::InvalidArguments, "#{full_filename} is invalid"
        end
      end

      validate_server_version

      output = { 'version' => '1.1' }

      [
        Resources::Certificate,
        Resources::Consumer,
        Resources::Upstream,
        Resources::Service,
        Resources::Plugin
      ].each { |clname| export_class(clname, output) }

      if output_file == '-'
        STDOUT.puts output.to_yaml
      else
        File.write(full_filename, output.to_yaml)
      end
    end

    desc 'import [OPTIONS] [INPUT|-]', 'Import a configuration from INPUT'
    option :test, type: :boolean, desc: "Don't do anything, just show what would happen"
    def import(input_file = '-')
      raw ||= acquire_input(input_file, options['verbose'])

      # rubocop:disable Security/YAMLLoad
      input = YAML.load(raw)
      # rubocop:enable Security/YAMLLoad

      validate_config_version input['version']

      [
        Resources::Certificate,
        Resources::Consumer,
        Resources::Upstream,
        Resources::Service,
        Resources::Plugin
      ].each { |clname| import_class(clname, input) }
    end

    desc(
      'migrate [OPTIONS] [INPUT|-] [OUTPUT|-]',
      'Migrate an older config from INPUT to OUTPUT'
    )
    def migrate(input_file = '-', output_file = '-')
      raw ||= acquire_input(input_file, options['verbose'])

      # rubocop:disable Security/YAMLLoad
      input = YAML.load(raw)
      # rubocop:enable Security/YAMLLoad

      validate_migrate_version input['version']

      output = migrate_config(input)

      if output_file == '-'
        STDERR.puts '[INFO] Outputting to STDOUT' if options['verbose']
        STDOUT.puts output.to_yaml
      else
        full_filename = File.expand_path(output_file)
        dirname = File.dirname(full_filename)
        unless File.exist?(dirname) && File.ftype(dirname) == 'directory'
          raise Exceptions::InvalidArguments, "#{full_filename} is invalid"
        end

        File.write(full_filename, output.to_yaml)
      end
    end

    private

    def export_class(class_name, output_data)
      STDERR.puts "[INFO] Processing #{class_name.route_key}" if options['verbose']
      output_data[class_name.route_key] = class_name.all.collect(&:export)
    end

    def import_class(class_name, import_data)
      STDERR.puts "[INFO] Processing #{class_name.route_key}" if options['verbose']
      class_name.batch_import(
        import_data[class_name.route_key],
        verbose: options['verbose'],
        test: options['test']
      )
    end

    # Used to pull input from either STDIN or the specified file
    def acquire_input(input_file, verbose = false)
      if input_file == '-'
        STDERR.puts '[INFO] Reading from STDIN' if verbose
        STDIN.read
      else
        full_filename = File.expand_path(input_file)
        unless File.exist?(full_filename) && File.ftype(full_filename) == 'file'
          raise Exceptions::InvalidArguments, "#{full_filename} is invalid"
        end

        begin
          File.read(full_filename)
        rescue StandardError => e
          raise "Unable to process #{relative_path}: #{e.message}"
        end
      end
    end

    def validate_config_version(version)
      if version && version == '1.1'
        validate_server_version
      elsif version && ['0.14', '1.0'].include?(version)
        STDERR.puts '[CRITICAL] Config version is too old. Try `migrate` instead of `import`.'
        exit 2
      else
        STDERR.puts '[CRITICAL] Config version is unknown or not supported.'
        exit 3
      end
    end

    def validate_migrate_version(version)
      if version && version == '0.14'
        true
      else
        STDERR.puts '[CRITICAL] Config version must be 0.14 for migration.'
        exit 4
      end
    end

    def validate_server_version
      if SkullIsland::APIClient.about_service['version'].start_with? '1.1'
        true
      else
        STDERR.puts '[CRITICAL] Server version mismatch!'
        exit 1
      end
    end
  end
end
