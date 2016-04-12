require 'spec_helper'

describe "acts_as_tagger" do
  before do
    clean_database!
  end

  describe "Tagger Method Generation" do
    before do
      @tagger = TaggableUser.new()
    end

    it "should add #is_tagger? query method to the class-side" do
      TaggableUser.should respond_to(:is_tagger?)
    end

    it "should return true from the class-side #is_tagger?" do
      TaggableUser.is_tagger?.should be true
    end

    it "should return false from the base #is_tagger?" do
      ActiveRecord::Base.is_tagger?.should be false
    end

    it "should add #is_tagger? query method to the singleton" do
      @tagger.should respond_to(:is_tagger?)
    end

    it "should add #tag method on the instance-side" do
      @tagger.should respond_to(:tag)
    end

    it "should generate an association for #owned_taggings and #owned_tags" do
      @tagger.should respond_to(:owned_taggings, :owned_tags)
    end
  end

  describe "#tag" do
    context 'when called with a non-existent tag context' do
      before(:each) do
        @tagger = TaggableUser.new()
        @taggable = TaggableModel.new(:name=>"Richard Prior")
      end

      it "should raise an exception" do
        lambda { @taggable.tag_list_on(:foo) }.should raise_error
      end

      it "should show all the tag list when both public and owned tags exist" do
        @taggable.tag_list = 'ruby, python'
        @tagger.tag(@taggable, :with => 'java, lisp', :on => :tags)
        @taggable.all_tags_on(:tags).map(&:value).sort.should == %w(ruby python java lisp).sort
      end

      it "should not add owned tags to the common list" do
        @taggable.tag_list = 'ruby, python'
        @tagger.tag(@taggable, :with => 'java, lisp', :on => :tags)
        @taggable.tag_list.should == %w(ruby python)
        @tagger.tag(@taggable, :with => '', :on => :tags)
        @taggable.tag_list.should == %w(ruby python)
      end

    end

    describe "when called by multiple tagger's" do
      before(:each) do
        @user_x = TaggableUser.create(:name => "User X")
        @user_y = TaggableUser.create(:name => "User Y")
        @taggable = TaggableModel.create(:name => 'tagtical', :tag_list => 'plugin')

        @user_x.tag(@taggable, :with => 'ruby, rails',  :on => :tags)
        @user_y.tag(@taggable, :with => 'ruby, plugin', :on => :tags)

        @user_y.tag(@taggable, :with => '', :on => :tags)
        @user_y.tag(@taggable, :with => '', :on => :tags)
      end

      it "should delete owned tags" do
        @user_y.owned_tags.should == []
      end

      it "should not delete other taggers tags" do
        expect(@user_x.owned_tags.size).to eq 2
      end

      it "should not delete original tags" do
        @taggable.all_tags_list_on(:tags).should include('plugin')
      end
    end
  end
end
