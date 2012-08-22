class TagticalMigration < ActiveRecord::Migration
  def self.up
    create_table :tags do |t|
      t.column :value, :string
      t.column :type, :string, :limit => 100
    end
    add_index :tags, [:type, :value], :unique => true
    add_index :tags, :value

    create_table :taggings do |t|
      t.column :relevance, :float
      t.column :tag_id, :integer
      t.column :taggable_id, :integer
      t.column :tagger_id, :integer
      t.column :tagger_type, :string, :limit => 100 if Tagtical.config.polymorphic_tagger?
      
      # You should make sure that the column created is
      # long enough to store the required class names.
      t.column :taggable_type, :string, :limit => 100
      
      t.column :created_at, :datetime
    end
    
    add_index :taggings, :tag_id
    add_index :taggings, [:taggable_id, :taggable_type]
    add_index :taggings, Tagtical.config.polymorphic_tagger? ? [:tagger_id, :tagger_type] : [:tagger_id]
  end
  
  def self.down
    drop_table :taggings
    drop_table :tags
  end

end
