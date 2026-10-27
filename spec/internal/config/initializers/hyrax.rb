# frozen_string_literal: true

Hyrax.config do |config|
  config.disable_wings = true
  config.file_set_model = 'Hyrax::FileSet'
  config.admin_set_model = 'Hyrax::AdministrativeSet'
  config.collection_model = 'Hyrax::PcdmCollection'
end
