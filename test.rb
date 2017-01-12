require "httparty"

@pd_api_token = "fLKofhk73AwW3Md2yh_P"
@pd_escalation_policy_id = ["PJXN8C6"]
@pd_schedule_id = ["PWS2SK2"]
@pd_url = "https://api.pagerduty.com"
@pd_user_id = ["PQW6XH7"]

def on_call(api_token, user_ids, escalation_policy_ids, schedule_ids)
  # Check the regular on call schedule first for on call times
  scheduled = HTTParty.get(
    "https://api.pagerduty.com/oncalls",
    :headers => {
      "Accept" => "application/vnd.pagerduty+json;version=2",
      "Authorization" => "Token token=fLKofhk73AwW3Md2yh_P"
    },
    :query => {
      "time_zone" => "EST",
      "user_ids" => ["PQW6XH7"],
      "escalation_policy_ids" => ["PJXN8C6"],
      "schedule_ids" => ["PWS2SK2"],
      "until" => "#{Time.now + (60 * 60 * 24 * 50)}"
    }
  )["oncalls"][0]

  next_on_call_times = {}

  if scheduled == nil
    puts "no on call found for the time period specified - #{Time.now} to #{Time.now + (60 * 60 * 24 * 50)}"
  else
    next_on_call_times["start"] = scheduled["start"]
    next_on_call_times["end"] = scheduled["end"]
  end

  return next_on_call_times
end

puts on_call(@pd_api_token, @pd_user_id, @pd_escalation_policy_id, @pd_schedule_id)