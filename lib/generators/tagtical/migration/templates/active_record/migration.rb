class TagticalMigration < ActiveRecord::Migration
  def self.up
    create_table :tags do |t|
      t.string :value
      t.string :type, :limit => 100
    end
    add_index :tags, [:type, :value], :unique => true
    add_index :tags, :value

    create_table :taggings do |t|
      t.float :relevance
      t.references :tag

      # You should make sure that the column created is
      # long enough to store the required class names.
      t.references :taggable, :polymorphic => true, :limit => 100
      if Tagtical.config.polymorphic_tagger?
        t.references :tagger, :polymorphic => true, :limit => 100
      else
        t.integer :tagger_id
      end

      t.datetime :created_at
    end

    add_index :taggings, :tag_id
    add_index :taggings, [:taggable_id, :taggable_type]
    add_index :taggings,  Tagtical.config.polymorphic_tagger? ? [:tagger_id, :tagger_type] : [:tagger_id]
  end

  def self.down
    drop_table :taggings
    drop_table :tags
  end
end
