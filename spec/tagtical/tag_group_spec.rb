require File.expand_path('../../spec_helper', __FILE__)

describe Tagtical::Taggable::TagGroup do

  before { clean_database! }

  it "should retrieve related tagged objects" do
    group = CustomGroup.create!(language_list: "ruby", skill_list: "programmer")
    objects = [
      {:name => "One", language_list: "ruby, c", skill_list: "programmer"},
      {:name => "Two", language_list: "c", skill_list: "programmer"},
      {:name => "Three", language_list: "ruby", skill_list: "manager"},
      {:name => "Four", language_list: "ruby", skill_list: "programmer"}
    ].map { |attrs| TaggableModel.create!(attrs) }
    group.taggable_models.should == [objects[0], objects[3]]
  end

  it "should retrieve associated tag groups" do
    groups = [
      {language_list: "ruby, c", skill_list: "programmer", name: "Ruby C Programmer"},
      {language_list: "c", skill_list: "programmer", name: "C Programmer"},
      {language_list: "ruby", skill_list: "manager", name: "Ruby Manager"},
      {language_list: "ruby", skill_list: "programmer", name: "Ruby Programmer"}
    ].map { |attrs| CustomGroup.create!(attrs) }
    model = TaggableModel.create!(language_list: "ruby, c", skill_list: "programmer")
    model.custom_groups.should == [groups[0], groups[1], groups[3]]
  end

end
