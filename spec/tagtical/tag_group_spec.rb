require File.expand_path('../../spec_helper', __FILE__)

describe Tagtical::TagGroup do

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

end
