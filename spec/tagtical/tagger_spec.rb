require File.expand_path('../../spec_helper', __FILE__)

describe "Tagger" do
  before(:each) do
    clean_database!
    @user = TaggableUser.create
    @taggable = TaggableModel.create(:name => "Bob Jones")
  end

  it "should have taggings" do
    @user.tag(@taggable, :with=>'ruby,scheme', :on=>:tags)
    @user.owned_taggings.size == 2
  end

  it "should have tags" do
    @user.tag(@taggable, :with=>'ruby,scheme', :on=>:tags)
    @user.owned_tags.size == 2
  end

  it "should not overlap tags from different taggers" do
    @user2 = TaggableUser.new
    lambda{
      @user.tag(@taggable, :with => 'ruby, scheme', :on => :tags)
      @user2.tag(@taggable, :with => 'java, python, lisp, ruby', :on => :tags)
    }.should change(Tagtical::Tagging, :count).by(6)

    [@user, @user2, @taggable].each(&:reload)

    @user.owned_tags.map(&:value).sort.should == %w(ruby scheme).sort
    @user2.owned_tags.map(&:value).sort.should == %w(java python lisp ruby).sort

    @taggable.tags_from(@user).sort.should == %w(ruby scheme).sort
    @taggable.tags_from(@user2).sort.should == %w(java lisp python ruby).sort

    @taggable.all_tags_list.sort.should == %w(ruby scheme java python lisp).sort
    @taggable.all_tags_on(:tags).size.should == 5
  end

  it "should not lose tags from different taggers" do
    @user2 = TaggableUser.create
    @user2.tag(@taggable, :with => 'java, python, lisp, ruby', :on => :tags)
    @user.tag(@taggable, :with => 'ruby, scheme', :on => :tags)

    lambda {
      @user2.tag(@taggable, :with => 'java, python, lisp', :on => :tags)
    }.should change(Tagtical::Tagging, :count).by(-1)

    [@user, @user2, @taggable].each(&:reload)

    @taggable.tags_from(@user).sort.should == %w(ruby scheme).sort
    @taggable.tags_from(@user2).sort.should == %w(java python lisp).sort

    @taggable.all_tags_list.sort.should == %w(ruby scheme java python lisp).sort
    @taggable.all_tags_on(:tags).length.should == 5
  end

  it "should not lose tags" do
    @user2 = TaggableUser.create

    @user.tag(@taggable, :with => 'awesome', :on => :tags)
    @user2.tag(@taggable, :with => 'awesome, epic', :on => :tags)

    lambda {
      @user2.tag(@taggable, :with => 'epic', :on => :tags)
    }.should change(Tagtical::Tagging, :count).by(-1)

    @taggable.reload
    @taggable.all_tags_list.should include('awesome')
    @taggable.all_tags_list.should include('epic')
  end

  it "is tagger" do
    @user.is_tagger?.should be_true
  end

end