# == Schema Information
#
# Table name: plan_details
#
#  id         :integer          not null, primary key
#  request_id :integer          default(0), not null
#  week       :integer          not null
#  percentage :integer          default(80), not null
#  ok_mon     :boolean          default(TRUE), not null
#  ok_tue     :boolean          default(TRUE), not null
#  ok_wed     :boolean          default(TRUE), not null
#  ok_thu     :boolean          default(TRUE), not null
#  ok_fri     :boolean          default(TRUE), not null
#  ok_sat     :boolean          default(FALSE), not null
#  ok_sun     :boolean          default(FALSE), not null
#

class PlanDetail < ActiveRecord::Base
  unloadable

  include Redmine::I18n

  belongs_to :request, :class_name => 'PlanRequest', :foreign_key => 'request_id'

  validates_uniqueness_of :week, :scope => [:request_id]

  attr_protected :request_id, :year, :week, :week_start_date

  default_scope { order(:week) }

  scope :week_range, lambda { |startweek, endweek|
    where("week >= :startweek AND week <= :endweek",
      :startweek => plan_week(startweek), :endweek => plan_week(endweek))
  }

  scope :request_states, lambda { |states|
    joins(:request).where("plan_requests.status IN (?)", states)
  }

  scope :user_details, lambda { |user, states, startweek, endweek|
    request_states(states).includes(:request => :task).where(
      "plan_requests.resource_id = :user_id",
      :user_id => user.is_a?(User) ? user.id : user
    ).week_range(startweek, endweek).order("plan_requests.id")
  }

  scope :group_overview, lambda { |group, states, startweek, endweek|
    request_states(states).select(
      "SUM(percentage) AS percentage, resource_id, week"
    ).group("resource_id, week").where(
      "plan_requests.resource_id IN (" +
        "SELECT user_id FROM plan_group_members WHERE plan_group_id = :group_id) ",
      :group_id => group.is_a?(PlanGroup) ? group.id : group
    ).week_range(startweek, endweek)
  }

  scope :task_details, lambda { |task, states, startweek, endweek|
    request_states(states).includes(:request, :request => :task).where(
      "plan_requests.task_id = :task_id",
      :task_id => task.is_a?(PlanTask) ? task.id : task
    ).week_range(startweek, endweek).order("plan_requests.id")
  }

  scope :user_req_workload, lambda { |req, states|
    joins(:request).select(
      "SUM(percentage) AS percentage, week"
    ).where(
      "plan_requests.resource_id = :user_id" +
      " AND (plan_requests.status IN (:states) OR plan_requests.id = :req_id)" +
      " AND week IN (SELECT week FROM plan_details WHERE request_id = :req_id)",
      :user_id => req.resource_id, :req_id => req.id, :states => states
    ).group(:week)
  }

  def self.plan_week(date)
    return date if date.is_a? Numeric
    date.cwyear * 100 + date.cweek
  end

  def self.bulk_update(request, detail_params, num)
    detail_list = []

    start_date = detail_params[:week_start_date]
    if start_date
      date = Date.parse(start_date)
    else
      date = Date.commercial(detail_params[:year].to_i, detail_params[:week].to_i, 1)
    end

    num.times do
      detail = self.where(:request_id => request.id, :week => plan_week(date)).first_or_initialize
      detail.update_attributes(detail_params)
      detail_list << detail
      date += 7
    end
    detail_list
  end

  def cwyear
    week / 100
  end

  def cweek
    week % 100
  end

  def week_start_date
    return nil if week == nil
    Date.commercial(self.cwyear, self.cweek, 1)
  end

  def week_start_date=(str)
    date = Date.parse(str)
    self.week = date.cwyear * 100 + date.cweek
  end

  def can_edit?
    request.can_edit?
  end
end
