# name: dl-teaser
# about: Provides methods for teasing the content behind a secured category.
# version: 0.1
# authors: Joe Buhlig
# url: https://github.com/discourse-league/dl-teaser

enabled_site_setting :dl_teaser_enabled

register_asset 'stylesheets/dl-teaser.scss'

after_initialize do

  class ::Category
    def self.reset_teasing_cache
      @allowed_teasing_cache["allowed"] =
        begin
          Set.new(
            CategoryCustomField
              .where(name: "enable_topic_teasing", value: "true")
              .pluck(:category_id)
          )
        end
    end

    @allowed_teasing_cache = DistributedCache.new("allowed_topic_teasing")

    def self.can_tease?(category_id)
      return false unless SiteSetting.dl_teaser_enabled

      unless set = @allowed_teasing_cache["allowed"]
        set = reset_teasing_cache
      end
      set.include?(category_id)
    end

    after_save :reset_teasing_cache


    protected
    def reset_teasing_cache
      ::Category.reset_teasing_cache
    end
  end

  require_dependency 'guardian'
  module ::CategoryGuardian
    alias_method :super_allowed_category_ids, :allowed_category_ids

    def allowed_category_ids
      ids = super_allowed_category_ids
      Category.find_each do |category|
        if SiteSetting.dl_teaser_enabled && category.custom_fields["enable_topic_teasing"] == "true"
          ids.push(category.id)
        end
      end
      return ids
    end

    alias_method :super_secure_category_ids, :secure_category_ids

    def secure_category_ids
      ids = super_secure_category_ids
      Category.unscoped.all.find_each do |category|
        if SiteSetting.dl_teaser_enabled && category.custom_fields["enable_topic_teasing"] == "true"
          ids.push(category.id)
        end
      end
      return ids
    end

  end

  require_dependency 'topic'
  class ::Topic

    def teased?(user)
      if self.archetype == "private_message"
        group_access = true
        category_teasing = false
      else
        if !user
          group_access = false
        elsif (user && self.category && self.category.category_groups && self.category.category_groups.pluck(:group_id).length > 0)
          group_access = (self.category.category_groups.pluck(:group_id) & user.groups.pluck(:id)).length > 0
        else
          group_access = true
        end
        category = Category.find(category_id)
        category_teasing = !category.custom_fields.nil?
        category_teasing = !category.custom_fields["enable_topic_teasing"].nil? if category_teasing
        category_teasing = category.custom_fields["enable_topic_teasing"] if category_teasing
      end

      SiteSetting.dl_teaser_enabled && category_teasing && !group_access
    end

    def topic_teasing_url
      if category_id
        Category.find(category_id).custom_fields["topic_teasing_url"] || "/"
      else
        ""
      end
    end

    def topic_teasing_icon
      if category_id
        Category.find(category_id).custom_fields["topic_teasing_icon"] || "shield"
      else
        ""
      end
    end

  end

  add_to_serializer(:topic_view, :teased) { object.topic.teased?(scope.user) }
  add_to_serializer(:topic_view, :topic_teasing_url) { object.topic.topic_teasing_url }
  add_to_serializer(:topic_view, :topic_teasing_icon) { object.topic.topic_teasing_icon }
  add_to_serializer(:topic_list_item, :teased) { object.teased?(scope.user) }
  add_to_serializer(:topic_list_item, :topic_teasing_url) { object.topic_teasing_url }
  add_to_serializer(:topic_list_item, :topic_teasing_icon) { object.topic_teasing_icon }

  require_dependency 'topics_controller'
  class ::TopicsController
    before_action :check_teaser, only: :show

    def check_teaser
      topic_view = TopicView.new(params[:id] || params[:topic_id], current_user)
      if topic_view.topic.category
        url = topic_view.topic.category.custom_fields["topic_teasing_url"] || "/"
        redirect_to url if topic_view.topic.teased?(current_user)
      end
    end
  end

end
