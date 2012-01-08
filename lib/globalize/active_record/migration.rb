module Globalize
  module ActiveRecord
    module Migration
      def create_translation_table!(fields)
        translated_attribute_names.each do |f|
          raise MigrationMissingTranslatedField, "Missing translated field #{f}" unless fields[f]
        end

        fields.each do |name, type|
          if translated_attribute_names.include?(name) && ![:string, :text].include?(type)
            raise BadMigrationFieldType, "Bad field type for #{name}, should be :string or :text"
          end
        end

        self.connection.create_table(translation_table_name) do |t|
          t.references table_name.sub(/^#{table_name_prefix}/, "").singularize
          t.string :locale
          fields.each do |name, type|
            t.column name, type
          end
          t.timestamps
        end

        self.connection.add_index(
          translation_table_name, 
          "#{table_name.sub(/^#{table_name_prefix}/, "").singularize}_id, locale",
          :name => translation_index_name,
          :unique => true
        )
      end

      def translation_index_name
        require 'digest/sha1'
        # FIXME what's the max size of an index name?
        index_name = "index_#{translation_table_name}_on_#{self.table_name.singularize}_id"
        index_name.size < 50 ? index_name : "index_#{Digest::SHA1.hexdigest(index_name)}"
      end

      def drop_translation_table!
        self.connection.remove_index(translation_table_name, :name => translation_index_name) rescue nil
        self.connection.drop_table(translation_table_name)
      end

      # seeding of existing data into translations
      def move_data_to_translation_table
        klass = self.class_name.constantize
        return unless klass.count > 0
        translated_attribute_columns = klass.first.translated_attributes.keys
        klass.all.each do |p|
          attribs = {}
          translated_attribute_columns.each { |c| attribs[c] = p.read_attribute(c) }
          p.update_attributes(attribs)
        end
      end

      def move_data_to_model_table
        # Find all of the translated attributes for all records in the model.
        klass = self.class_name.constantize
        return unless klass.count > 0
        all_translated_attributes = klass.all.collect{|m| m.attributes}
        all_translated_attributes.each do |translated_record|
          # Create a hash containing the translated column names and their values.
          translated_attribute_names.inject(fields_to_update={}) do |f, name|
            f.update({name.to_sym => translated_record[name.to_s]})
          end

          # Now, update the actual model's record with the hash.
          klass.update_all(fields_to_update, {:id => translated_record['id']})
        end
      end
      
    end
  end
end
