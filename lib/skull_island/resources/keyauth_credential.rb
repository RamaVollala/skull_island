# frozen_string_literal: true

module SkullIsland
  # Resource classes go here...
  module Resources
    # The KeyauthCredential resource class
    #
    # @see https://docs.konghq.com/hub/kong-inc/key-auth/ Key-Auth API definition
    class KeyauthCredential < Resource
      property :key, validate: true
      property(
        :consumer_id,
        required: true, validate: true, preprocess: true, postprocess: true, as: :consumer
      )
      property :created_at, read_only: true, postprocess: true

      def self.batch_import(data, verbose: false, test: false)
        raise(Exceptions::InvalidArguments) unless data.is_a?(Array)

        data.each_with_index do |resource_data, index|
          resource = new
          resource.key = resource_data['key']
          resource.delayed_set(:consumer, resource_data, 'consumer_id')
          resource.import_update_or_skip(index: index, verbose: verbose, test: test)
        end
      end

      def self.get(id, options = {})
        if options[:consumer]&.is_a?(Consumer)
          options[:consumer].target(id)
        elsif options[:consumer]
          consumer_opts = options.merge(lazy: true)
          Consumer.get(options[:consumer], consumer_opts).target(id)
        end
      end

      def self.relative_uri
        'key-auths'
      end

      def relative_uri
        consumer ? "#{consumer.relative_uri}/key-auth/#{id}" : nil
      end

      def save_uri
        consumer ? "#{consumer.relative_uri}/key-auth" : nil
      end

      def export(options = {})
        hash = { 'key' => key }
        hash['consumer_id'] = "<%= lookup :consumer, '#{consumer.username}' %>" if consumer
        [*options[:exclude]].each do |exclude|
          hash.delete(exclude.to_s)
        end
        [*options[:include]].each do |inc|
          hash[inc.to_s] = send(inc.to_sym)
        end
        hash.reject { |_, value| value.nil? }
      end

      # Keys can't be updated, only created or deleted
      def modified_existing?
        false
      end

      private

      def postprocess_consumer_id(value)
        if value.is_a?(String)
          Consumer.new(
            entity: { 'id' => value },
            lazy: true,
            tainted: false
          )
        else
          value
        end
      end

      def preprocess_consumer_id(input)
        if input.is_a?(String)
          input
        else
          input.id
        end
      end

      # Used to validate {#consumer} on set
      def validate_consumer_id(value)
        # allow either a Consumer object or a String
        value.is_a?(Consumer) || value.is_a?(String)
      end

      # Used to validate {#key} on set
      def validate_key(value)
        # allow a String
        value.is_a?(String)
      end
    end
  end
end
